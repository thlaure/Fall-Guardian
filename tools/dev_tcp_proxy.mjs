import net from 'node:net';

const [listenHost, listenPort, targetHost, targetPort] = process.argv.slice(2);

if (!listenHost || !listenPort || !targetHost || !targetPort) {
  console.error(
    'Usage: node tools/dev_tcp_proxy.mjs <listen-host> <listen-port> <target-host> <target-port>',
  );
  process.exit(64);
}

const server = net.createServer((client) => {
  const target = net.createConnection(
    { host: targetHost, port: Number(targetPort) },
    () => client.pipe(target).pipe(client),
  );

  const closeBoth = () => {
    client.destroy();
    target.destroy();
  };

  client.on('error', closeBoth);
  target.on('error', closeBoth);
});

server.listen(Number(listenPort), listenHost, () => {
  console.log(
    `Proxy listening on ${listenHost}:${listenPort} -> ${targetHost}:${targetPort}`,
  );
});
