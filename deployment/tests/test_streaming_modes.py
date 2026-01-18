#!/usr/bin/env python3
"""
Test script for validating both streaming and non-streaming modes of the chat API.
"""

import json
import requests
import time

BASE_URL = "http://localhost:8000"

def test_non_streaming_mode():
    """Test non-streaming mode (stream=false)"""
    print("=== Testing Non-Streaming Mode (stream=false) ===")

    try:
        response = requests.post(
            f"{BASE_URL}/api/chat/send",
            json={
                "message": "What is machine learning?",
                "stream": False
            },
            timeout=60
        )

        print(f"Status Code: {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            print("Response format: JSON")
            print(f"Response length: {len(data.get('response', ''))}")
            print(f"Backend: {data.get('backend')}")
            print(f"Status: {data.get('status')}")
            print("Sample content:", data.get('response', '')[:100] + "..." if len(data.get('response', '')) > 100 else data.get('response', ''))
            return True
        else:
            print(f"Error: {response.text}")
            return False

    except Exception as e:
        print(f"Error: {e}")
        return False

def test_streaming_mode():
    """Test streaming mode (stream=true)"""
    print("\n=== Testing Streaming Mode (stream=true) ===")

    try:
        response = requests.post(
            f"{BASE_URL}/api/chat/send",
            json={
                "message": "How can you help me?",
                "stream": True
            },
            stream=True,
            timeout=60
        )

        print(f"Status Code: {response.status_code}")

        if response.status_code == 200:
            print("Response format: Server-Sent Events")
            content_chunks = []

            for line in response.iter_lines():
                if line:
                    line_str = line.decode('utf-8')
                    if line_str.startswith('data: '):
                        try:
                            data = json.loads(line_str[6:])
                            if 'content' in data:
                                content_chunks.append(data['content'])
                                print(data['content'], end='', flush=True)
                            elif 'done' in data:
                                print("\n[Stream completed]")
                                break
                            elif 'error' in data:
                                print(f"\n[Error: {data['error']}]")
                                return False
                        except json.JSONDecodeError:
                            continue

            full_content = ''.join(content_chunks)
            print(f"Total content length: {len(full_content)}")
            return True
        else:
            print(f"Error: {response.text}")
            return False

    except Exception as e:
        print(f"Error: {e}")
        return False

def test_default_mode():
    """Test default mode (no stream parameter)"""
    print("\n=== Testing Default Mode (no stream parameter) ===")

    try:
        response = requests.post(
            f"{BASE_URL}/api/chat/send",
            json={
                "message": "Hello world"
            },
            stream=True,
            timeout=60
        )

        print(f"Status Code: {response.status_code}")

        if response.status_code == 200:
            print("Response format: Should be streaming (default)")
            content_chunks = []

            for line in response.iter_lines():
                if line:
                    line_str = line.decode('utf-8')
                    if line_str.startswith('data: '):
                        try:
                            data = json.loads(line_str[6:])
                            if 'content' in data:
                                content_chunks.append(data['content'])
                                print(data['content'], end='', flush=True)
                            elif 'done' in data:
                                print("\n[Stream completed]")
                                break
                            elif 'error' in data:
                                print(f"\n[Error: {data['error']}]")
                                return False
                        except json.JSONDecodeError:
                            continue

            full_content = ''.join(content_chunks)
            print(f"Total content length: {len(full_content)}")
            return True
        else:
            print(f"Error: {response.text}")
            return False

    except Exception as e:
        print(f"Error: {e}")
        return False

def test_health_endpoint():
    """Test health endpoint"""
    print("\n=== Testing Health Endpoint ===")

    try:
        response = requests.get(f"{BASE_URL}/health", timeout=10)
        print(f"Status Code: {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            print(f"Health status: {data.get('status')}")
            print(f"App name: {data.get('app')}")
            return True
        else:
            print(f"Error: {response.text}")
            return False

    except Exception as e:
        print(f"Error: {e}")
        return False

def main():
    """Run all tests"""
    print("Starting API Tests...")
    print("=" * 50)

    results = {
        "health": test_health_endpoint(),
        "non_streaming": test_non_streaming_mode(),
        "streaming": test_streaming_mode(),
        "default": test_default_mode()
    }

    print("\n" + "=" * 50)
    print("TEST RESULTS:")
    for test_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{test_name}: {status}")

    all_passed = all(results.values())
    print(f"\nOverall: {'✅ ALL TESTS PASSED' if all_passed else '❌ SOME TESTS FAILED'}")

    return all_passed

if __name__ == "__main__":
    main()