#!/usr/bin/env python3
"""
Direct test to Databricks model - bypasses the backend entirely.
Shows exactly what the model returns: content blocks with annotations.

Usage:
    uv run python tests/test_direct_model.py "Your question here"
"""

import os
import sys
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

from openai import OpenAI

DATABRICKS_TOKEN = os.environ.get('DATABRICKS_TOKEN')
DATABRICKS_BASE_URL = os.environ.get('DATABRICKS_BASE_URL')
DATABRICKS_MODEL = os.environ.get('DATABRICKS_MODEL')

client = OpenAI(
    api_key=DATABRICKS_TOKEN,
    base_url=DATABRICKS_BASE_URL
)


def test_model_response(message: str):
    """
    Shows the complete model response structure.

    The model returns:
    - Multiple content blocks (text chunks)
    - Each content block may have annotations (citations)
    - Annotations contain: title, url, type
    """
    print("=" * 80)
    print(f"MODEL: {DATABRICKS_MODEL}")
    print(f"QUERY: {message}")
    print("=" * 80)
    print()

    response = client.responses.create(
        model=DATABRICKS_MODEL,
        input=[{"role": "user", "content": message}],
        stream=False
    )

    full_text = ""
    all_citations = []

    for output_msg in response.output:
        for idx, content in enumerate(output_msg.content):
            text = content.text if hasattr(content, 'text') else ''
            annotations = content.annotations if hasattr(content, 'annotations') else []

            # Track position in full text
            start_pos = len(full_text)
            full_text += text
            end_pos = len(full_text)

            # Print content block
            has_citation = "YES" if annotations else "no"
            print(f"[Block {idx}] Citation: {has_citation}")
            print(f"  Text: {repr(text[:100])}..." if len(text) > 100 else f"  Text: {repr(text)}")

            # Collect citations with position info
            for ann in annotations:
                citation = {
                    "content_index": idx,
                    "start_pos": start_pos,
                    "end_pos": end_pos,
                    "text": text,
                    "title": ann.title,
                    "url": ann.url,
                    "type": ann.type
                }
                all_citations.append(citation)
                print(f"  -> Citation: {ann.title}")
                print(f"     URL: {ann.url[:80]}...")
            print()

    print("=" * 80)
    print("FULL RESPONSE TEXT:")
    print("=" * 80)
    print(full_text)

    print()
    print("=" * 80)
    print(f"CITATIONS SUMMARY: {len(all_citations)} found")
    print("=" * 80)
    for i, c in enumerate(all_citations):
        print(f"\n[{i}] Block {c['content_index']}: chars {c['start_pos']}-{c['end_pos']}")
        print(f"    Title: {c['title']}")
        print(f"    Text: {repr(c['text'][:60])}...")

    return full_text, all_citations


def test_streaming_response(message: str):
    """
    Shows streaming response with annotations.

    In streaming mode:
    - ResponseTextDeltaEvent: text chunks
    - ResponseOutputTextAnnotationAddedEvent: citations with content_index
    """
    print()
    print("=" * 80)
    print("STREAMING MODE")
    print("=" * 80)
    print()

    response = client.responses.create(
        model=DATABRICKS_MODEL,
        input=[{"role": "user", "content": message}],
        stream=True
    )

    text_chunks = []  # List of text deltas
    annotations = []  # List of annotation events

    for chunk in response:
        event_type = type(chunk).__name__

        if event_type == 'ResponseTextDeltaEvent':
            delta = chunk.delta if hasattr(chunk, 'delta') else ''
            text_chunks.append(delta)
            # Print streaming text
            print(delta, end='', flush=True)

        elif 'Annotation' in event_type:
            ann = chunk.annotation if hasattr(chunk, 'annotation') else None
            content_idx = chunk.content_index if hasattr(chunk, 'content_index') else None
            if ann:
                annotations.append({
                    "content_index": content_idx,
                    "title": ann.title if hasattr(ann, 'title') else None,
                    "url": ann.url if hasattr(ann, 'url') else None,
                    "type": ann.type if hasattr(ann, 'type') else None
                })

    print("\n")
    print("=" * 80)
    print(f"STREAMING ANNOTATIONS: {len(annotations)} found")
    print("=" * 80)
    for i, a in enumerate(annotations):
        print(f"[{i}] Content Index: {a['content_index']}")
        print(f"    Title: {a['title']}")
        print(f"    URL: {a['url'][:80]}..." if a['url'] else "    URL: None")

    return ''.join(text_chunks), annotations


if __name__ == "__main__":
    query = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "What is the ethics hotline number?"

    # Test non-streaming (shows complete structure)
    full_text, citations = test_model_response(query)

    # Test streaming (shows real-time behavior)
    streaming_text, streaming_annotations = test_streaming_response(query)
