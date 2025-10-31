defmodule Rclip.Router do
  use Plug.Router

  plug(:match)

  plug(Plug.Parsers,
    parsers: [],
    pass: ["*/*"]
  )

  plug(:dispatch)

  get "/" do
    send_resp(conn, 200, """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>RClip — Remote Clipboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
    </head>
    <body class="bg-gray-100 min-h-screen p-4 flex flex-col items-center">

    <!-- Top row: Form + Active Clipboards -->
    <div class="flex flex-col md:flex-row gap-6 w-full max-w-6xl">
    <!-- Left: RClip Form -->
    <div class="flex-1 bg-white rounded-2xl shadow-lg p-6">
      <h1 class="text-4xl font-extrabold text-indigo-600 mb-2 text-center">RClip</h1>
      <p class="text-center text-gray-500 mb-6">Your ephemeral remote clipboard — text or files</p>

      <form id="clipboard-form" class="space-y-4">
        <div>
          <label for="clipboard-id" class="block text-sm font-medium text-gray-700">Clipboard ID</label>
          <input id="clipboard-id" name="id" type="text" required
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring focus:ring-indigo-200 focus:ring-opacity-50 p-2"
            placeholder="Enter unique ID">
        </div>

        <!-- Textarea container -->
        <div id="textarea-container">
          <label for="data-area" class="block text-sm font-medium text-gray-700">Content (text)</label>
          <textarea id="data-area" name="data" rows="8"
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring focus:ring-indigo-200 focus:ring-opacity-50 p-2"
            placeholder="Paste text or drag a file here"></textarea>
        </div>

        <!-- File preview container -->
        <div id="file-preview-container" class="hidden border p-4 rounded relative bg-gray-50">
          <span id="file-name" class="font-medium"></span>
          <button type="button" id="remove-file-btn"
            class="absolute top-1 right-1 text-gray-500 hover:text-red-600 font-bold">&times;</button>
        </div>

        <div class="flex flex-wrap gap-4">
          <div class="flex-1">
            <label for="ttl" class="block text-sm font-medium text-gray-700">TTL (seconds)</label>
            <input id="ttl" name="ttl" type="number" min="1" value="300"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring focus:ring-indigo-200 focus:ring-opacity-50 p-2">
          </div>
          <div class="flex items-center mt-5">
            <input id="once" name="once" type="checkbox" value="true" class="h-4 w-4 text-indigo-600 border-gray-300 rounded">
            <label for="once" class="ml-2 block text-sm text-gray-700">Fetch Once</label>
          </div>
          <div class="flex items-center mt-5">
            <input id="private" name="private" type="checkbox" value="true" class="h-4 w-4 text-red-600 border-gray-300 rounded">
            <label for="private" class="ml-2 block text-sm text-gray-700">Private</label>
          </div>
        </div>

        <button type="submit"
          class="w-full bg-indigo-600 text-white font-semibold py-2 px-4 rounded-lg shadow hover:bg-indigo-700 transition duration-150">
          Copy to RClip
        </button>

        <p id="status" class="mt-4 text-center text-green-600 font-medium hidden">Copied!</p>
      </form>
    </div>

    <!-- Right: Active Clipboards -->
    <div class="w-full md:w-80 bg-gray-50 rounded-xl p-4 shadow overflow-y-auto max-h-[600px]">
      <h2 class="text-xl font-bold mb-2">Active Clipboards</h2>
      <div id="active-clipboards" class="space-y-2"></div>
    </div>
    </div>

    <!-- Bottom row: cURL panel -->
    <div class="mt-6 w-full max-w-6xl bg-gray-50 border rounded-lg p-4 shadow flex flex-col gap-4">
    <h3 class="text-lg font-bold">cURL Examples</h3>

    <div class="flex items-center gap-2">
      <pre id="curl-post" class="flex-1 bg-gray-100 p-2 rounded text-sm overflow-x-auto">curl -X POST "http://localhost/your-id?ttl=300&once=false&private=false" -d "Hello World"</pre>
      <button id="copy-curl-post" class="bg-indigo-600 text-white px-2 py-1 rounded hover:bg-indigo-700 text-sm">Copy</button>
    </div>

    <div class="flex items-center gap-2">
      <pre id="curl-get" class="flex-1 bg-gray-100 p-2 rounded text-sm overflow-x-auto">curl "http://localhost/your-id"</pre>
      <button id="copy-curl-get" class="bg-indigo-600 text-white px-2 py-1 rounded hover:bg-indigo-700 text-sm">Copy</button>
    </div>
    </div>

    <!-- Toast -->
    <div id="toast" class="fixed bottom-6 right-6 bg-green-600 text-white px-4 py-2 rounded shadow opacity-0 pointer-events-none transition-opacity duration-300 z-50">
    Copied!
    </div>

    <script>
    const form = document.getElementById('clipboard-form');
    const status = document.getElementById('status');
    const textareaContainer = document.getElementById('textarea-container');
    const textarea = document.getElementById('data-area');
    const filePreviewContainer = document.getElementById('file-preview-container');
    const fileNameEl = document.getElementById('file-name');
    const removeFileBtn = document.getElementById('remove-file-btn');
    let activeFile = null;

    const activeContainer = document.getElementById("active-clipboards");
    const toast = document.getElementById("toast");

    function showToast(message, event) {
    toast.textContent = message;
    toast.classList.remove("opacity-0");
    toast.classList.add("opacity-100");
    setTimeout(() => toast.classList.remove("opacity-100"), 1500);
    }

    function showStatus(msg, success=true) {
    status.textContent = msg;
    showToast(msg);
    status.classList.remove('hidden');
    status.classList.toggle('text-green-600', success);
    status.classList.toggle('text-red-600', !success);
    setTimeout(() => status.classList.add('hidden'), 2500);
    }

    function guessMimeType(filename) {
    const ext = filename.split('.').pop().toLowerCase();
    const map = {png:'image/png', jpg:'image/jpeg', jpeg:'image/jpeg', gif:'image/gif', bmp:'image/bmp', webp:'image/webp', txt:'text/plain', md:'text/markdown', pdf:'application/pdf', mp4:'video/mp4'};
    return map[ext] || 'application/octet-stream';
    }

    function removeActiveFile() {
    activeFile = null;
    filePreviewContainer.classList.add('hidden');
    textareaContainer.classList.remove('hidden');
    textarea.value = '';
    }

    removeFileBtn.addEventListener('click', removeActiveFile);

    // Drag & drop
    textarea.addEventListener('dragover', e => e.preventDefault());
    textarea.addEventListener('drop', e => {
    e.preventDefault();
    const files = e.dataTransfer.files;
    if (files.length > 0) {
    activeFile = files[0];
    fileNameEl.textContent = activeFile.name;
    textareaContainer.classList.add('hidden');
    filePreviewContainer.classList.remove('hidden');
    }
    });

    // Paste handling
    textarea.addEventListener('paste', async (e) => {
    const items = e.clipboardData.items;
    for (const item of items) {
    if (item.kind === 'file') {
      activeFile = item.getAsFile();
      fileNameEl.textContent = activeFile.name || 'clipboard-file';
      textareaContainer.classList.add('hidden');
      filePreviewContainer.classList.remove('hidden');
      e.preventDefault();
      return;
    }
    }
    });

    // Form submission
    form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const id = document.getElementById('clipboard-id').value.trim();
    const ttl = document.getElementById('ttl').value;
    const once = document.getElementById('once').checked ? "true" : "false";
    const isPrivate = document.getElementById('private').checked ? "true" : "false";
    if (!id) return;

    let url = `/${encodeURIComponent(id)}?ttl=${ttl}&once=${once}&private=${isPrivate}`;
    let body, contentType;

    if (activeFile) {
    body = await activeFile.arrayBuffer();
    contentType = activeFile.type || guessMimeType(activeFile.name);
    } else {
    body = textarea.value;
    contentType = 'text/plain';
    }

    try {
    const resp = await fetch(url, { method: 'POST', headers: { 'Content-Type': contentType }, body: body });
    if (resp.ok) {
      showStatus("Copied to RClip!");
      removeActiveFile();
      textarea.value = '';
      document.getElementById('ttl').value = 300;
      document.getElementById('once').checked = false;
      document.getElementById('private').checked = false;
      fetchActiveClipboards();
    } else showStatus("Failed to copy!", false);
    } catch(err) { console.error(err); showStatus("Error copying!", false); }
    });

    document.getElementById('clipboard-id').focus();

    // Fetch active non-private clipboards
    async function fetchActiveClipboards() {
    try {
    const resp = await fetch("/active");
    if (!resp.ok) return;
    const clipboards = await resp.json();
    activeContainer.innerHTML = "";
    clipboards.forEach(cb => {
      const card = document.createElement("div");
      card.className = "p-2 bg-white rounded shadow flex justify-between items-center";

      const info = document.createElement("div");
      info.innerHTML = `<div class="font-medium">${cb.id}</div><div class="text-gray-500 text-sm">${cb.content_type}</div>`;
      card.appendChild(info);

      const actions = document.createElement("div");
      if(cb.content_type.startsWith("text/")) {
        const btn = document.createElement("button");
        btn.textContent = "Copy";
        btn.className = "ml-2 text-sm px-2 py-1 bg-indigo-600 text-white rounded hover:bg-indigo-700";
        btn.onclick = async () => {
          const res = await fetch(`/${cb.id}`);
          const text = await res.text();
          await navigator.clipboard.writeText(text);
          showToast(`Copied "${cb.id}"`);
        };
        actions.appendChild(btn);
      } else if(cb.content_type.startsWith("image/")) {
        const btn = document.createElement("button");
        btn.textContent = "Copy";
        btn.className = "ml-2 text-sm px-2 py-1 bg-green-600 text-white rounded hover:bg-green-700";
        btn.onclick = async () => {
          const res = await fetch(`/${cb.id}`);
          const blob = await res.blob();
          await navigator.clipboard.write([new ClipboardItem({ [cb.content_type]: blob })]);
          showToast(`Copied image "${cb.id}"`);
        };
        actions.appendChild(btn);
      }
      const dl = document.createElement("a");
      dl.textContent = "Download";
      dl.href = `/${cb.id}`;
      dl.download = cb.id;
      dl.className = "ml-2 text-sm text-gray-700 underline";
      actions.appendChild(dl);

      card.appendChild(actions);
      activeContainer.appendChild(card);
    });
    } catch(err) { console.error("Failed to fetch active clipboards", err); }
    }

    fetchActiveClipboards();
    setInterval(fetchActiveClipboards, 5000);

    // cURL panel
    const curlPostEl = document.getElementById("curl-post");
    const curlGetEl = document.getElementById("curl-get");
    const copyCurlPostBtn = document.getElementById("copy-curl-post");
    const copyCurlGetBtn = document.getElementById("copy-curl-get");
    const clipboardIdInput = document.getElementById("clipboard-id");

    function updateCurlExamples() {
    const id = clipboardIdInput.value.trim() || "your-id";
    curlPostEl.textContent = `curl -X POST "https://rclip.feveile-hauge.dk/${id}?ttl=300&once=false&private=false" -d "Hello World"`;
    curlGetEl.textContent = `curl "https://rclip.feveile-hauge.dk/${id}"`;
    }
    updateCurlExamples();
    clipboardIdInput.addEventListener("input", updateCurlExamples);

    copyCurlPostBtn.addEventListener("click", async () => {
    await navigator.clipboard.writeText(curlPostEl.textContent);
    showToast("Copied cURL POST");
    });
    copyCurlGetBtn.addEventListener("click", async () => {
    await navigator.clipboard.writeText(curlGetEl.textContent);
    showToast("Copied cURL GET");
    });

    </script>
    </body>
    </html>
    """)
  end

  get "/active" do
    # return list of %{id, content_type, ...} excluding private
    clipboards = Rclip.Store.list_active()
    send_resp(conn, 200, Jason.encode!(clipboards))
  end

  # ===========================
  # New long-polling route
  # ===========================
  get "/next/:id" do
    id = conn.params["id"]

    # Subscribe current process to clipboard updates
    :ok = Rclip.Store.subscribe(id)

    # Wait for the next update, up to a maximum timeout
    receive do
      {:clipboard_update, %{data: data, content_type: content_type}} ->
        conn
        |> put_resp_content_type(content_type)
        |> send_resp(200, data)
    after
      # 60s timeout
      60_000 ->
        # no content if nothing changed
        send_resp(conn, 204, "")
    end
  end

  get "/:id" do
    case Rclip.Store.get(id) do
      {:ok, %{data: data, content_type: content_type}} ->
        conn
        |> put_resp_content_type(content_type)
        |> send_resp(200, data)

      :not_found ->
        send_resp(conn, 404, "Clipboard not found or expired")
    end
  end

  post "/:id" do
    ttl = parse_int(get_query_param(conn, "ttl") || "300")
    once = get_query_param(conn, "once") == "true"
    private = get_query_param(conn, "private") == "true"

    {:ok, body, _conn} = read_full_body(conn)
    content_type = Plug.Conn.get_req_header(conn, "content-type") |> List.first() || "text/plain"
    ip = Tuple.to_list(conn.remote_ip) |> Enum.join(".")

    Rclip.Store.put(id, body, ip, content_type, ttl, private, once)

    send_resp(conn, 200, "Copied into clipboard #{id}")
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  # Reads the full body, works for large files
  defp read_full_body(conn) do
    read_body_loop(conn, <<>>)
  end

  defp read_body_loop(conn, acc) do
    case Plug.Conn.read_body(conn, length: 10_000_000) do
      {:ok, body, conn} ->
        {:ok, acc <> body, conn}

      {:more, partial, conn} ->
        read_body_loop(conn, acc <> partial)
    end
  end

  defp get_query_param(conn, key), do: conn.params[key]
  defp parse_int(str), do: Integer.parse(str) |> elem(0)
end
