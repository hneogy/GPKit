# Serves the playground page on this computer with the headers the plan proposes for /playground/* on the site, so the
# page is tried under its real policy: python3 -I playground/serve.py PORT DIR (the module, from CI, in DIR beside it).
import http.server, functools, sys

CSP = ("default-src 'none'; style-src 'self'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self'; "
       "font-src 'self'; img-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm'}
    def end_headers(self):
        self.send_header('Content-Security-Policy', CSP)
        self.send_header('Permissions-Policy', 'geolocation=()')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

port, root = int(sys.argv[1]), sys.argv[2]
http.server.ThreadingHTTPServer(('127.0.0.1', port), functools.partial(Handler, directory=root)).serve_forever()
