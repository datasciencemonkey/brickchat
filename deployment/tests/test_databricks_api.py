#!/usr/bin/env python3
"""
Test script for direct Databricks API interaction to validate response structures.
"""

from openai import OpenAI
import os
from dotenv import load_dotenv

load_dotenv()

# Configuration
DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL', 'https://adb-984752964297111.11.azuredatabricks.net/serving-endpoints')
DATABRICKS_MODEL = os.environ.get('DATABRICKS_MODEL')

def test_databricks_streaming():
    """Test direct Databricks API with streaming enabled"""
    print("=== Testing Databricks Streaming API ===")

    if not DATABRICKS_TOKEN:
        print("❌ DATABRICKS_TOKEN not found in environment")
        return False

    try:
        client = OpenAI(
            api_key=DATABRICKS_TOKEN,
            base_url=DATABRICKS_BASE_URL
        )

        response = client.responses.create(
            model=DATABRICKS_MODEL,
            input=[
                {
                    "role": "user",
                    "content": "What are the latest growth numbers for the company?"
                }
            ],
            stream=True
        )

        print("✅ Streaming response created successfully")
        print("Streaming response:\n")
        print("-" * 60)

        # Collect streamed content and annotations
        content_parts = []
        annotations = []  # List of unique annotations for the references section
        annotation_map = {}  # Map annotation data to citation number

        for chunk in response:
            chunk_type = getattr(chunk, 'type', 'unknown')

            # Stream text delta to console
            if chunk_type == 'response.output_text.delta':
                if hasattr(chunk, 'delta') and chunk.delta:
                    content_parts.append(chunk.delta)
                    print(chunk.delta, end='', flush=True)

            # Capture annotations (citations) and insert inline reference
            elif chunk_type == 'response.output_text.annotation.added':
                if hasattr(chunk, 'annotation') and chunk.annotation:
                    annotation_data = chunk.annotation

                    # Create a unique key for deduplication (based on title + url)
                    if isinstance(annotation_data, dict):
                        ann_key = (annotation_data.get('title', ''), annotation_data.get('url', ''))
                    else:
                        ann_key = str(annotation_data)

                    # Check if we've seen this annotation before
                    if ann_key not in annotation_map:
                        citation_num = len(annotations) + 1
                        annotation_map[ann_key] = citation_num
                        annotations.append({
                            'citation_num': citation_num,
                            'content_index': getattr(chunk, 'content_index', None),
                            'annotation': annotation_data
                        })
                    else:
                        citation_num = annotation_map[ann_key]

                    # Insert inline citation reference
                    inline_ref = f" [{citation_num}]"
                    content_parts.append(inline_ref)
                    print(inline_ref, end='', flush=True)

        print("\n" + "-" * 60)

        # Build the full response with inline citations
        full_response = ''.join(content_parts)
        print(f"\n✅ Response complete ({len(full_response)} characters)")

        # Display references section
        if annotations:
            print(f"\n📚 References ({len(annotations)} sources):")
            print("=" * 60)
            for ann in annotations:
                citation_num = ann['citation_num']
                annotation_data = ann['annotation']
                if isinstance(annotation_data, dict):
                    title = annotation_data.get('title', 'Untitled')
                    url = annotation_data.get('url', 'N/A')
                    print(f"\n  [{citation_num}] {title}")
                    print(f"      {url}")
                else:
                    print(f"\n  [{citation_num}] {annotation_data}")
        else:
            print("\nℹ️ No citations found in response")

        # Return structured result
        result = {
            'response': full_response,
            'references': [
                {
                    'num': ann['citation_num'],
                    'title': ann['annotation'].get('title', '') if isinstance(ann['annotation'], dict) else str(ann['annotation']),
                    'url': ann['annotation'].get('url', '') if isinstance(ann['annotation'], dict) else '',
                    'type': ann['annotation'].get('type', '') if isinstance(ann['annotation'], dict) else 'unknown'
                }
                for ann in annotations
            ]
        }

        print("\n\n📋 Structured Result:")
        print(f"Response length: {len(result['response'])} chars")
        print(f"References: {len(result['references'])}")

        return True

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_databricks_non_streaming():
    """Test direct Databricks API with streaming disabled"""
    print("\n=== Testing Databricks Non-Streaming API ===")

    if not DATABRICKS_TOKEN:
        print("❌ DATABRICKS_TOKEN not found in environment")
        return False

    try:
        client = OpenAI(
            api_key=DATABRICKS_TOKEN,
            base_url=DATABRICKS_BASE_URL
        )

        response = client.responses.create(
            model=DATABRICKS_MODEL,
            input=[
                {
                    "role": "user",
                    "content": "Explain machine learning in simple terms"
                }
            ],
            stream=False
        )

        print("✅ Non-streaming response created successfully")
        print(f"Response type: {type(response)}")

        if hasattr(response, 'output') and response.output:
            print(f"Number of output messages: {len(response.output)}")

            for i, output_message in enumerate(response.output):
                print(f"Message {i + 1}:")
                if hasattr(output_message, 'content') and output_message.content:
                    print(f"  Content items: {len(output_message.content)}")

                    for j, content_item in enumerate(output_message.content):
                        if hasattr(content_item, 'text') and content_item.text:
                            text_preview = content_item.text[:100] + "..." if len(content_item.text) > 100 else content_item.text
                            print(f"    Text {j + 1}: {text_preview}")

        return True

    except Exception as e:
        print(f"❌ Error: {e}")
        return False

def test_conversation_history():
    """Test API with conversation history"""
    print("\n=== Testing Databricks API with Conversation History ===")

    if not DATABRICKS_TOKEN:
        print("❌ DATABRICKS_TOKEN not found in environment")
        return False

    try:
        client = OpenAI(
            api_key=DATABRICKS_TOKEN,
            base_url=DATABRICKS_BASE_URL
        )

        # Multi-turn conversation
        conversation = [
            {
                "role": "user",
                "content": "Hello"
            },
            {
                "role": "assistant",
                "content": "Hello! How can I help you today?"
            },
            {
                "role": "user",
                "content": "What products do you sell?"
            }
        ]

        response = client.responses.create(
            model=DATABRICKS_MODEL,
            input=conversation,
            stream=False
        )

        print("✅ Conversation history test successful")

        if hasattr(response, 'output') and response.output:
            for output_message in response.output:
                if hasattr(output_message, 'content') and output_message.content:
                    for content_item in output_message.content:
                        if hasattr(content_item, 'text') and content_item.text:
                            preview = content_item.text[:200] + "..." if len(content_item.text) > 200 else content_item.text
                            print(f"Response: {preview}")

        return True

    except Exception as e:
        print(f"❌ Error: {e}")
        return False

def main():
    """Run all Databricks API tests"""
    print("Starting Databricks API Tests...")
    print("=" * 50)

    # Check environment
    print(f"DATABRICKS_TOKEN: {'✅ Set' if DATABRICKS_TOKEN else '❌ Missing'}")
    print(f"DATABRICKS_BASE_URL: {DATABRICKS_BASE_URL}")
    print(f"DATABRICKS_MODEL: {DATABRICKS_MODEL or '❌ Missing'}")
    print()

    if not DATABRICKS_TOKEN or not DATABRICKS_MODEL:
        print("❌ Missing required environment variables")
        return False

    results = {
        "streaming": test_databricks_streaming(),
        # "non_streaming": test_databricks_non_streaming(),
        # "conversation_history": test_conversation_history()
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