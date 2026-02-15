"""
Unit tests for TCPServer in whisper_stream.py
"""
import pytest
import socket
import json
import threading
import time
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from whisper_stream import TCPServer


class TestTCPServer:
    """Test TCP server functionality."""

    @pytest.fixture
    def unused_port(self):
        """Get an unused port for testing."""
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(('127.0.0.1', 0))
            return s.getsockname()[1]

    @pytest.fixture
    def server(self, unused_port):
        """Create and yield a test server, cleanup after."""
        srv = TCPServer(unused_port)
        yield srv
        srv.close()

    def test_server_creation(self, unused_port):
        """Should create server on specified port."""
        server = TCPServer(unused_port)
        assert server.port == unused_port
        assert server.client_socket is None
        server.close()

    def test_wait_for_client_timeout(self, server):
        """Should timeout if no client connects."""
        result = server.wait_for_client(timeout=0.1)
        assert result is False
        assert server.client_socket is None

    def test_wait_for_client_success(self, server):
        """Should accept client connection."""
        # Connect a client in background
        def connect_client():
            time.sleep(0.1)
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.connect(('127.0.0.1', server.port))
            time.sleep(0.5)  # Keep connection open
            client.close()

        client_thread = threading.Thread(target=connect_client)
        client_thread.start()

        result = server.wait_for_client(timeout=1.0)
        assert result is True
        assert server.client_socket is not None

        client_thread.join()

    def test_send_event_no_client(self, server):
        """Should handle send when no client connected."""
        result = server.send_event("test", data="value")
        assert result is True  # Returns True when no client

    def test_send_event_with_client(self, server):
        """Should send JSON event to connected client."""
        # Connect client and capture data
        received_data = []

        def client_receiver():
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.connect(('127.0.0.1', server.port))
            data = client.recv(1024).decode('utf-8')
            received_data.append(data)
            client.close()

        # Start client
        client_thread = threading.Thread(target=client_receiver)
        client_thread.start()

        # Wait for connection
        server.wait_for_client(timeout=1.0)

        # Send event
        result = server.send_event("test_event", foo="bar", num=42)
        assert result is True

        client_thread.join(timeout=1.0)

        # Verify received data
        assert len(received_data) > 0
        event = json.loads(received_data[0].strip())
        assert event["type"] == "test_event"
        assert event["foo"] == "bar"
        assert event["num"] == 42

    def test_receive_command_no_client(self, server):
        """Should return None when no client connected."""
        result = server.receive_command(timeout=0.1)
        assert result is None

    def test_receive_command_timeout(self, server):
        """Should return None on timeout."""
        # Connect client but don't send data
        def connect_only():
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.connect(('127.0.0.1', server.port))
            time.sleep(0.5)
            client.close()

        client_thread = threading.Thread(target=connect_only)
        client_thread.start()

        server.wait_for_client(timeout=1.0)
        result = server.receive_command(timeout=0.1)
        assert result is None

        client_thread.join()

    def test_receive_command_success(self, server):
        """Should receive and parse JSON command."""
        def send_command():
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.connect(('127.0.0.1', server.port))
            time.sleep(0.1)
            cmd = {"command": "start_recording"}
            client.sendall((json.dumps(cmd) + "\n").encode('utf-8'))
            time.sleep(0.5)
            client.close()

        client_thread = threading.Thread(target=send_command)
        client_thread.start()

        server.wait_for_client(timeout=1.0)
        result = server.receive_command(timeout=1.0)

        assert result is not None
        assert result["command"] == "start_recording"

        client_thread.join()

    def test_close_cleans_up(self, server):
        """Should close all sockets."""
        server.close()
        # Attempting to use closed server should not crash
        # (testing it doesn't raise exceptions)
        server.close()  # Should handle double-close

    def test_wait_for_reconnect(self, server):
        """Should handle client reconnection."""
        # First connection
        def first_client():
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.connect(('127.0.0.1', server.port))
            time.sleep(0.2)
            client.close()

        threading.Thread(target=first_client).start()
        server.wait_for_client(timeout=1.0)
        old_socket = server.client_socket

        # Reconnect
        def second_client():
            time.sleep(0.1)
            client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            client.connect(('127.0.0.1', server.port))
            time.sleep(0.2)
            client.close()

        threading.Thread(target=second_client).start()
        result = server.wait_for_reconnect(timeout=1.0)

        assert result is True
        assert server.client_socket is not old_socket
