/**
 * MCPheonix Durable Objects Worker
 * 
 * This Cloudflare Worker script implements the interface between the MCPheonix
 * Elixir application and Cloudflare Durable Objects, providing an HTTP and WebSocket
 * API for interacting with Durable Objects.
 */

// Define the Durable Object class
export class MCPheonixObject {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.storage = state.storage;
    this.sessions = new Map(); // WebSocket sessions
  }

  // Handle HTTP requests
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    console.log(`Durable Object received request: ${request.method} ${path}`);

    // WebSocket upgrade
    if (request.headers.get("Upgrade") === "websocket") {
      return this.handleWebSocketUpgrade(request);
    }

    // Handle HTTP methods
    if (request.method === "GET") {
      return this.handleGet(path, url.searchParams);
    } else if (request.method === "POST") {
      return this.handlePost(path, await request.json());
    } else if (request.method === "PUT") {
      return this.handlePut(path, await request.json());
    } else if (request.method === "DELETE") {
      return this.handleDelete(path);
    } else {
      return new Response("Method not allowed", { status: 405 });
    }
  }

  // Handle GET requests
  async handleGet(path, params) {
    // Get state or specific key
    if (path === "/state") {
      const data = await this.storage.list();
      return new Response(JSON.stringify({ data }), {
        headers: { "Content-Type": "application/json" }
      });
    } else if (path.startsWith("/state/")) {
      const key = path.substring(7);
      const value = await this.storage.get(key);
      
      if (value === undefined) {
        return new Response("Key not found", { status: 404 });
      }
      
      return new Response(JSON.stringify({ key, value }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    return new Response("Not found", { status: 404 });
  }

  // Handle POST requests
  async handlePost(path, data) {
    // Custom method calls
    if (path.startsWith("/method/")) {
      const method = path.substring(8);
      
      // Check if method exists on this class
      if (typeof this[method] === "function" && method.startsWith("method_")) {
        try {
          const result = await this[method](data);
          return new Response(JSON.stringify({ success: true, result }), {
            headers: { "Content-Type": "application/json" }
          });
        } catch (error) {
          return new Response(JSON.stringify({ success: false, error: error.message }), {
            status: 500,
            headers: { "Content-Type": "application/json" }
          });
        }
      } else {
        return new Response(JSON.stringify({ success: false, error: "Method not found" }), {
          status: 404,
          headers: { "Content-Type": "application/json" }
        });
      }
    }
    
    return new Response("Not found", { status: 404 });
  }

  // Handle PUT requests
  async handlePut(path, data) {
    // Update state
    if (path.startsWith("/state/")) {
      const key = path.substring(7);
      
      await this.storage.put(key, data.value);
      
      // Notify connected clients
      this.broadcastUpdate(key, data.value);
      
      return new Response(JSON.stringify({ success: true, key }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    return new Response("Not found", { status: 404 });
  }

  // Handle DELETE requests
  async handleDelete(path) {
    // Delete state
    if (path.startsWith("/state/")) {
      const key = path.substring(7);
      
      await this.storage.delete(key);
      
      // Notify connected clients
      this.broadcastUpdate(key, null);
      
      return new Response(JSON.stringify({ success: true, key }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    return new Response("Not found", { status: 404 });
  }

  // Handle WebSocket connections
  async handleWebSocketUpgrade(request) {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    
    // Accept the WebSocket connection
    server.accept();
    
    // Generate a session ID
    const sessionId = crypto.randomUUID();
    
    // Store the WebSocket
    this.sessions.set(sessionId, server);
    
    // Set up event handlers
    server.addEventListener("message", async event => {
      try {
        const message = JSON.parse(event.data);
        
        // Handle different message types
        if (message.type === "method") {
          // Call a method on this class
          if (typeof this[message.method] === "function" && message.method.startsWith("method_")) {
            try {
              const result = await this[message.method](message.params);
              server.send(JSON.stringify({
                type: "response",
                id: message.id,
                success: true,
                result
              }));
            } catch (error) {
              server.send(JSON.stringify({
                type: "response",
                id: message.id,
                success: false,
                error: error.message
              }));
            }
          } else {
            server.send(JSON.stringify({
              type: "response",
              id: message.id,
              success: false,
              error: "Method not found"
            }));
          }
        }
      } catch (error) {
        console.error("Error handling WebSocket message:", error);
        server.send(JSON.stringify({
          type: "error",
          error: "Failed to process message"
        }));
      }
    });
    
    // Handle WebSocket close
    server.addEventListener("close", () => {
      this.sessions.delete(sessionId);
    });
    
    // Handle WebSocket error
    server.addEventListener("error", () => {
      this.sessions.delete(sessionId);
    });
    
    // Send initial state
    const data = await this.storage.list();
    server.send(JSON.stringify({
      type: "init",
      state: data
    }));
    
    return new Response(null, {
      status: 101,
      webSocket: client
    });
  }

  // Broadcast an update to all connected WebSocket clients
  broadcastUpdate(key, value) {
    const update = JSON.stringify({
      type: "update",
      key,
      value,
      timestamp: new Date().toISOString()
    });
    
    for (const client of this.sessions.values()) {
      client.send(update);
    }
  }

  // Custom methods that can be called via HTTP or WebSocket

  // Example method: echo
  async method_echo(data) {
    console.log("Echo method called with data:", data);
    return data;
  }

  // Example method: increment counter
  async method_increment(data) {
    const key = data.key || "counter";
    const increment = data.increment || 1;
    
    // Get current value
    let value = await this.storage.get(key) || 0;
    
    // Increment value
    value += increment;
    
    // Store new value
    await this.storage.put(key, value);
    
    // Notify connected clients
    this.broadcastUpdate(key, value);
    
    return { key, value };
  }
}

// Main Worker script
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    console.log(`Worker received request: ${request.method} ${path}`);
    
    // Route requests to appropriate Durable Object
    if (path.startsWith("/object/")) {
      // Extract object ID from path
      const parts = path.split("/");
      if (parts.length < 3) {
        return new Response("Invalid object ID", { status: 400 });
      }
      
      const objectId = parts[2];
      
      // Construct a stub for the Durable Object
      const objectStub = env.MCPHEONIX_OBJECT.get(env.MCPHEONIX_OBJECT.idFromName(objectId));
      
      // Remove /object/{id} prefix from path
      const newUrl = new URL(request.url);
      newUrl.pathname = "/" + parts.slice(3).join("/");
      
      // Forward the request to the Durable Object
      const newRequest = new Request(newUrl, request);
      return objectStub.fetch(newRequest);
    }
    
    // Initialize a new Durable Object
    if (path.startsWith("/initialize/")) {
      const objectId = path.substring(12);
      
      if (request.method !== "POST") {
        return new Response("Method not allowed", { status: 405 });
      }
      
      // Create a stub for the Durable Object
      const objectStub = env.MCPHEONIX_OBJECT.get(env.MCPHEONIX_OBJECT.idFromName(objectId));
      
      // Get the initial data
      const data = await request.json();
      
      // Initialize the Durable Object by storing the initial data
      const initRequest = new Request(`https://${url.hostname}/state`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data)
      });
      
      return objectStub.fetch(initRequest);
    }
    
    return new Response("Not found", { status: 404 });
  }
}; 