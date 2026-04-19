# Fragile
A Fragile is not fragile - It is a precisely defined HTTP/1.1 implementation in Zig.

## Philosophy
Most servers are permissive.  
They accept garbage, guess intent, and recover from ambiguity.

Fragile rejects this.

Invalid input is rejected. Ambiguity is not resolved.

What appears fragile is precision.

The behavior is fixed. The boundaries are defined. Nothing is implicit.  
Fragile accepts bytes. It defines boundaries. It rejects ambiguity.

> No libc.  
> Boundary is the kernel.

## Requirements
- Zig 0.15.2
- Linux (epoll; Tested with Gentoo 6.12.21)

## Running
```
zig build run
curl http://localhost:8080
```

## Architecture
Fragile is structured as a strict separation of concerns.  
Each layer has a single responsibility and does not depend on higher layers.

- `main` initializes the process and defines the entry point.
- `server/loop` drives the system using epoll. It does not interpret data.
- `server/connection` represents a connection as a state machine.
- `http/parser` transforms bytes into structured data. It is pure and has no IO.
- `http/request` defines the shape of a request. It contains no behavior.
- `http/response` defines the response and handles serialization.

### Data flows

```mermaid
flowchart LR
    A[bytes] --> B[parser]
    B -->|valid| C[Request]
    B -->|invalid| D[reject]
    C --> E[handler]
    E --> F[Response]
    F --> G[bytes]
```

### Lifecycle
```mermaid
flowchart LR
    E[epoll wat] -->|event| L[listener]
    L -->|accept| FD[fd]
    FD -->|init| C[Connection]

    C -->|EPOLLIN| R[reading]
    R -->|parse success| W[writing]
    R -->|invalid| X[closing]

    W -->|write complete| X
```

No layer guesses intent.  
No layer corrects invalid input.  
If the structure is not defined, it is rejected.  

This architecture makes boundaries explicit.

### Structure

```
src/
  main.zig
  net/
    epoll.zig       -- wait, add, del
    listener.zig    -- init, accept
    socket.zig      -- read, write, close
  server/
    connection.zig  -- state machine
    loop.zig        -- flow control
  http/
    parser.zig      -- bytes → Request
    request.zig     -- data
    response.zig    -- Response → bytes
```

### Dependency

```
main
 └─ server/loop
     ├─ net/epoll
     ├─ net/listener
     ├─ net/socket
     ├─ server/connection
     │   └─ net/socket
     └─ http/parser
         └─ http/request
```

Each layer does exactly one thing. Nothing more.  
The structure is not an implementation detail. It is the system.

## License
Copyright KEI SAWAMURA 2026.  
Fragile is licensed under the MIT License. Use, copy, and modify freely.
