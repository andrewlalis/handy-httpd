import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.net.URI;

/**
 * Simple java program for stress-testing the handy-httpd static file server.
 */
class Tester {
    public static void main(String[] args) throws Exception {
		// testEndpoint("/", 100, 200);
		// testEndpoint("/style.css", 100, 200);
		// testEndpoint("/spaceshuttle.png", 100, 200);
		// testEndpoint("/unknown", 1, 404);
		testEndpointParallel("/index.html", 500, 200, 10);
    }
	
	private static void testEndpoint(String endpoint, int requestCount, int expectedStatus) throws Exception {
		long totalTime = 0;
		for (int i = 0; i < requestCount; i++) {
			HttpClient client = HttpClient.newHttpClient();
			HttpRequest request = HttpRequest.newBuilder()
				.uri(URI.create("http://localhost:8080" + endpoint))
				.GET()
				.timeout(Duration.ofSeconds(5))
				.build();
			try {
				long start = System.currentTimeMillis();
				HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
				long dur = System.currentTimeMillis() - start;
				totalTime += dur;
				if (response.statusCode() != expectedStatus) {
					System.out.printf("Unexpected status code %d on endpoint %s\n", response.statusCode(), endpoint);
				}
			} catch (Exception e) {
				e.printStackTrace();
			}
		}
		double msPerRequest = ((double) totalTime) / requestCount;
		System.out.println("Average of " + msPerRequest + " ms per request.");
	}

	private static void testEndpointParallel(String endpoint, int requestCount, int expectedStatus, int threadCount) throws Exception {
		for (int i = 0; i < threadCount; i++) {
			new Thread(() -> {
				try {
					testEndpoint(endpoint, requestCount, expectedStatus);
				} catch (Exception e) {
					e.printStackTrace();
				}
			}).start();
		}
	}
}