import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpRequest.BodyPublishers;
import java.net.http.HttpResponse.BodyHandlers;
import java.nio.file.Files;
import java.nio.file.Path;

class Tests {
    private static final HttpClient httpClient = HttpClient.newHttpClient();
    public static void main(String[] args) throws Exception {
        buildServer();
        Process serverProcess = new ProcessBuilder("./server")
            .inheritIO()
            .start();
        if (!waitUntilOnline()) {
            serverProcess.destroy();
            return;
        }
        System.out.println("Server is online!");

        int testsFailed = 0;

        if (!testFileUpload()) {
            testsFailed++;
        }
        if (!testFileDownload()) {
            testsFailed++;
        }

        shutdownServer();
        int serverExitCode = serverProcess.waitFor();
        System.out.println("Server exited with code " + serverExitCode);

        if (testsFailed > 0) {
            System.exit(1);
        }
    }

    private static void buildServer() throws Exception {
        Process buildProcess = new ProcessBuilder("dub", "build", "--single", "server.d")
            .inheritIO()
            .start();
        int result = buildProcess.waitFor();
        if (result != 0) {
            throw new Exception("Build failed.");
        }
    }

    private static boolean waitUntilOnline() throws Exception {
        int attempts = 0;
        while (attempts < 100) {
            try {
                HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:8080/ready")).GET().build();
                HttpResponse<String> response = httpClient.send(request, BodyHandlers.ofString());
                if (response.statusCode() == 200) {
                    return true;
                }
            } catch (Exception e) {
                // Skip this.
            }
            System.out.println("Waiting for server to go online...");
            attempts++;
            Thread.sleep(100);
        }
        return false;
    }

    private static void shutdownServer() throws Exception {
        HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:8080/shutdown")).POST(BodyPublishers.noBody()).build();
        httpClient.send(request, BodyHandlers.discarding());
    }

    private static boolean testFileUpload() throws Exception {
        System.out.println("Starting file upload test.");
        final var filePath = Path.of("sample-files", "sample-1.txt");
        try (var in = Files.newInputStream(filePath)) {
            HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:8080/upload"))
                .POST(BodyPublishers.ofInputStream(() -> in))
                .header("Content-Type", "text/plain")
                .header("Transfer-Encoding", "chunked")
                .build();
            HttpResponse<String> response = httpClient.send(request, BodyHandlers.ofString());
            if (response.statusCode() != 200) {
                System.out.println("Incorrect status code: " + response.statusCode());
                return false;
            }
            final var uploadedFile = Path.of("uploaded-file.txt");
            if (Files.notExists(uploadedFile)) {
                System.out.println("Uploaded file doesn't exist.");
                return false;
            }
            if (Files.size(filePath) != Files.size(uploadedFile)) {
                System.out.println("Uploaded file doesn't have same size as original.");
                return false;
            }
        }
        System.out.println("File upload test successful.");
        return true;
    }

    private static boolean testFileDownload() throws Exception {
        System.out.println("Starting file download test.");
        HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:8080/source")).GET().build();
        HttpResponse<String> response = httpClient.send(request, BodyHandlers.ofString());
        if (response.statusCode() != 200) {
            System.out.println("Incorrect status code: " + response.statusCode());
            return false;
        }
        String expectedBody = Files.readString(Path.of("server.d"));
        if (!response.body().equals(expectedBody)) {
            System.out.println("Response body doesn't match expected.");
            return false;
        }
        System.out.println("File download test successful.");
        return true;
    }
}