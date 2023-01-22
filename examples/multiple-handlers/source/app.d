import handy_httpd;
import handy_httpd.handlers.path_delegating_handler;

void main() {
	auto pathHandler = new PathDelegatingHandler();
	pathHandler.addMapping("/users", &handleUsers);
	pathHandler.addMapping("/items", &handleItems);
	auto server = new HttpServer(pathHandler);
	server.start();
}

void handleUsers(ref HttpRequestContext ctx) {
	ctx.response.writeBody("You're on the /users page.");
}

void handleItems(ref HttpRequestContext ctx) {
	ctx.response.writeBody("You're on the /items page.");
}
