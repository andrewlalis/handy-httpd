import handy_httpd;
import handy_httpd.handlers.path_handler;
import slf4d;

void main() {
	auto pathHandler = new PathHandler()
		.addMapping(Method.GET, "/users", &handleUsers)
		.addMapping(Method.GET, "/users/:userId:uint", &handleUser)
		.addMapping(Method.GET, "/items", &handleItems)
		.addMapping("/error", &handleWithError);
	auto server = new HttpServer(pathHandler);
	server.start();
}

void handleUsers(ref HttpRequestContext ctx) {
	ctx.response.writeBodyString("You're on the /users page.");
}

void handleUser(ref HttpRequestContext ctx) {
	ulong userId = ctx.request.getPathParamAs!ulong("userId");
	infoF!"User %d visited the page."(userId);
	ctx.response.writeBodyString("Hello user!");
}

void handleItems(ref HttpRequestContext ctx) {
	ctx.response.writeBodyString("You're on the /items page.");
}

void handleWithError(ref HttpRequestContext ctx) {
	ctx.response.writeBodyString("This worker has an error.");
	throw new Error("Oh no");
}
