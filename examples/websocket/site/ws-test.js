const messageBoxesContainer = document.getElementsByClassName("boxes-container")[0];
const WS_HOST = "ws://localhost:8080/ws";

function getRandomInt(min, max) {
    min = Math.ceil(min);
    max = Math.floor(max);
    return Math.floor(Math.random() * (max - min) + min);
}
  

function clearAllMessages() {
    messageBoxesContainer.innerHTML = "";
}

function addMessageBox(id, title) {
    const container = document.createElement("div");
    container.id = "message-box-container-" + id;
    container.className = "message-box-container";
    const header = document.createElement("h3");
    header.innerText = title;
    container.appendChild(header);
    const box = document.createElement("div");
    box.className = "message-box";
    box.id = "message-box-" + id;
    container.appendChild(box);

    messageBoxesContainer.appendChild(container);
}

function removeMessageBox(id) {
    const element = document.getElementById("message-box-container-" + id);
    element.parentElement.removeChild(element);
}

function addComment(id, text) {
    const element = document.createElement("strong");
    element.innerText = text;
    const paragraph = document.createElement("p");
    paragraph.appendChild(element);
    document.getElementById("message-box-" + id).appendChild(paragraph);
    paragraph.scrollIntoView();
}

function addMessage(id, msg) {
    const element = document.createElement("p");
    const now = new Date();
    element.innerText = now.toLocaleString() + ": " + msg;
    document.getElementById("message-box-" + id).appendChild(element);
    element.scrollIntoView();
}

function sendAndComment(ws, id, msg) {
    ws.send(msg);
    addComment(id, "Sent: \"" + msg + "\"");
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function testOneWebSocket(id) {
    addMessageBox(id, "WebSocket Test " + id);
    addComment(id, "Beginning WebSocket test...");
    addComment(id, `Connecting to ${WS_HOST}`);
    await sleep(getRandomInt(300, 600));
    const ws = new WebSocket(WS_HOST);
    ws.onopen = () => addComment(id, "Connected!");
    ws.onclose = () => addComment(id, "Closed!");
    ws.onerror = (err) => {
        console.error(id, err);
        addComment(id, "Error: " + err);
    }
    ws.onmessage = (msg) => {
        addMessage(id, msg.data);
    }
    await sleep(1000);
    addComment(id, "Ready state: " + ws.readyState);
    if (ws.readyState !== WebSocket.OPEN) {
        addComment(id, "Exiting because socket isn't open.")
        return; // Exit if we aren't able to continue the test.
    }
    for (let i = 1; i <= 1000; i++) {
        const sleepTime = getRandomInt(10, 500);
        addComment(id, `Waiting for ${sleepTime}ms before sending...`);
        await sleep(sleepTime);
        const msg = `Hello from tester ${id}. Msg #${i}`;
        sendAndComment(ws, id, msg);
    }
    ws.close();
}

async function testWebSockets() {
    clearAllMessages();
    const countInput = document.getElementById("count-input");
    const testerCount = parseInt(countInput.value);
    for (let i = 1; i <= testerCount; i++) {
        testOneWebSocket(i + "");
    }
}

const testButton = document.getElementById("test-button");
testButton.onclick = testWebSockets;
