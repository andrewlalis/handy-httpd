import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.URI;

/**
 * Simple java program for stress-testing the handy-httpd static file server.
 */
class Tester {
    public static void main(String[] args) throws Exception {
        System.out.println("Starting server...");
		Process p = new ProcessBuilder("dub", "run").start();
		Thread.sleep(1000);
		System.out.println("Beginning tests...");
		
		testEndpoint("/index.html", 1000, 200);
		
		p.destroyForcibly();
		p.waitFor();
		System.out.println("Done!");
    }
	
	private static void testEndpoint(String endpoint, int requestCount, int expectedStatus) throws Exception {
		for (int i = 0; i < requestCount; i++) {
			new Thread(() -> {
				HttpClient client = HttpClient.newHttpClient();
				HttpRequest request = HttpRequest.newBuilder()
					.uri(URI.create("http://localhost:8080" + endpoint))
					.GET()
					.build();
				try {
					long start = System.currentTimeMillis();
					HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
					long dur = System.currentTimeMillis() - start;
					System.out.println("Response received in " + dur + " ms");
					if (response.statusCode() != expectedStatus) {
						System.out.printf("Unexpected status code %d on endpoint %s\n", response.statusCode(), endpoint);
					}
				} catch (Exception e) {
					e.printStackTrace();
				}
			}).start();
		}
	}
}