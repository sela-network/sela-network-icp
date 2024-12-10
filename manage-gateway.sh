#!/bin/bash

# Start Redis if not running
if ! pgrep redis-server > /dev/null; then
    redis-server &
    sleep 2
fi

# Run the gateway
cd ic_websocket_gateway && RUST_BACKTRACE=1 cargo run 