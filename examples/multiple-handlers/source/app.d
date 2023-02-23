import handy_httpd;
import handy_httpd.handlers.path_delegating_handler;
import slf4d;

void main() {
	auto pathHandler = new PathDelegatingHandler();
	pathHandler.addMapping("/users", &handleUsers);
	pathHandler.addMapping("/users/{userId}", &handleUser);
	pathHandler.addMapping("/items", &handleItems);
	auto server = new HttpServer(pathHandler);
	server.start();
}

void handleUsers(ref HttpRequestContext ctx) {
	ctx.response.writeBodyString("You're on the /users page.");
}

void handleUser(ref HttpRequestContext ctx) {
	auto log = getLogger();
	ulong userId = ctx.request.getPathParamAs!ulong("userId");
	log.infoF!"User %d visited the page."(userId);
	ctx.response.writeBodyString("Hello user!");
}

void handleItems(ref HttpRequestContext ctx) {
	ctx.response.writeBodyString("You're on the /items page.");
}
