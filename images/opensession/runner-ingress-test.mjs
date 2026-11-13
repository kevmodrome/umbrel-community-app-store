import assert from 'node:assert/strict';

// Called after smoke-test.sh replaces the seed with the candidate image.
// A disposable Docker subnet supplies actual socket peers in the CGNAT range;
// it is NOT a real Tailscale enrollment or evidence of production isolation.
export async function testRunnerIngress({ docker, inside, image, name, origin }) {
  const network = `${name}-tailnet`;
  const client = `${name}-client`;
  let connected = false;
  let created = false;
  const run = (networkName, script, ip) => docker('run', '--rm', '--name', client,
    '--network', networkName, ...(ip ? ['--ip', ip] : []),
    '--entrypoint', 'bun', image, '-e', script);
  const clientPrelude = `import assert from 'node:assert/strict';
    const request = (path, options = {}) => fetch(base + path, {
      ...options, signal: AbortSignal.timeout(10000),
    });`;
  const registration = { name: 'disposable-ingress-fixture', platform: 'linux', arch: 'x64', capabilities: {} };
  const headers = { 'Content-Type': 'application/json', 'X-Forwarded-For': '100.127.252.3' };

  inside(`import os from 'node:os'; import assert from 'node:assert/strict';
    const ip=Object.values(os.networkInterfaces()).flat().find(x=>x.family==='IPv4'&&!x.internal).address;
    for (const port of [13852,2019]) {
      await assert.rejects(fetch('http://'+ip+':'+port+'/ready', {signal:AbortSignal.timeout(2000)}));
    }
    console.log('Backend and proxy admin are not remotely listening');`);
  inside(`import fs from 'node:fs'; import assert from 'node:assert/strict';
    const pid=fs.readdirSync('/proc').filter(x=>/^\\d+$/.test(x)).find(x=>{
      try { const args=fs.readFileSync('/proc/'+x+'/cmdline','utf8').split('\\0');
        return args.includes('server') && args[0].includes('opensession'); } catch { return false; }
    });
    assert.ok(pid);
    const env=fs.readFileSync('/proc/'+pid+'/environ','utf8').split('\\0');
    for (const value of ['HOST=127.0.0.1','PORT=13852','OPENSESSION_TRUST_FORWARDED_FOR=1']) assert.ok(env.includes(value),value);
    console.log('Fixed loopback backend and forwarded-header trust');`);

  for (const path of ['/api/runners/register', '/api/runners/heartbeat', '/runner-ws']) {
    const response = await fetch(origin + path, {
      method: path === '/runner-ws' ? 'GET' : 'POST', headers,
      ...(path === '/runner-ws' ? {} : { body: JSON.stringify(registration) }),
      signal: AbortSignal.timeout(10000),
    });
    assert.equal(response.status, 403, `browser ingress allowed ${path}`);
    assert.match(await response.text(), /dedicated Tailscale Runner endpoint/);
  }
  const response = await fetch(origin + '/api/runners/pair', {
    method: 'POST', headers: { Origin: origin }, signal: AbortSignal.timeout(10000),
  });
  assert.equal(response.status, 200);
  const { code } = await response.json();
  assert.ok(code, 'fixture pairing code missing');
  registration.code = code;
  const ordinaryIp = docker('inspect', '--format', '{{.NetworkSettings.IPAddress}}', name);

  try {
    // Test rejected non-tailnet traffic before connecting the trusted fixture.
    run('bridge', `${clientPrelude}
      const base=${JSON.stringify(`http://${ordinaryIp}:3851`)};
      for (const path of ['/api/runners/register','/api/runners/heartbeat','/runner-ws','/']) {
        const r=await request(path, {method:path==='/runner-ws'||path==='/'?'GET':'POST',
          headers:${JSON.stringify(headers)},
          ...(path==='/runner-ws'||path==='/'?{}:{body:${JSON.stringify(JSON.stringify(registration))}})});
        assert.equal(r.status,403,path);
        assert.match(await r.text(),/require a Tailscale source/);
      }
      console.log('Real non-tailnet peers and forged forwarded headers: rejected');`);

    docker('network', 'create', '--internal', '--subnet', '100.127.252.0/29', network);
    created = true;
    docker('network', 'connect', '--ip', '100.127.252.2', network, name);
    connected = true;
    run(network, `${clientPrelude}
      const base='http://100.127.252.2:3851';
      // Even a tailnet peer cannot reach the app, pair-code minting or terminals.
      for (const path of ['/','/api/health','/api/settings/general','/api/runners/pair','/ws']) {
        assert.equal((await request(path,{method:path.endsWith('/pair')?'POST':'GET'})).status,404,path);
      }
      const registration=await request('/api/runners/register', {method:'POST',
        headers:{'Content-Type':'application/json','X-Forwarded-For':'192.0.2.5, 127.0.0.1',
          'Forwarded':'for=192.0.2.5','X-Real-IP':'192.0.2.5'},
        body:${JSON.stringify(JSON.stringify(registration))}});
      assert.equal(registration.status,200,await registration.clone().text());
      const {runner,token}=await registration.json();
      assert.equal(runner.address,'100.127.252.3','upstream must see the actual socket peer');
      const auth={Authorization:'Bearer '+token,'X-OpenSession-Runner':runner.id,'Content-Type':'application/json'};
      assert.equal((await request('/api/runners/heartbeat',{method:'POST',headers:auth,body:'{}'})).status,200);
      assert.equal((await request('/api/runners/heartbeat',{method:'POST',body:'{}'})).status,401);
      assert.equal((await request('/runner-ws?id='+runner.id)).status,401);
      // Bun's WebSocket supports the same bearer header the real client uses.
      const socket=new WebSocket(base.replace('http:','ws:')+'/runner-ws?id='+runner.id,{headers:auth});
      await new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>{socket.close();reject(new Error('Runner WebSocket timed out'));},10000);
        socket.onopen=()=>{
          socket.send(JSON.stringify({t:'hello',version:1}));
          socket.send(JSON.stringify({t:'heartbeat'}));
        };
        socket.onerror=()=>{clearTimeout(timer);reject(new Error('Runner WebSocket failed'));};
        socket.onmessage=({data})=>{
          if(JSON.parse(data).t==='heartbeat_ack'){clearTimeout(timer);socket.close();resolve();}
        };
      });
      console.log('Registration, true origin, bearer heartbeat and authenticated WebSocket: passed');`, '100.127.252.3');
    console.log('Runner-only routing, source validation, header overwrite and upstream authentication: passed');
  } finally {
    // Also clean a client left behind by an interrupted Docker CLI.
    try { docker('rm', '--force', client); } catch {}
    if (connected) docker('network', 'disconnect', network, name);
    if (created) docker('network', 'rm', network);
  }
}
