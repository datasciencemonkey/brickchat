BrickChat UI — Feature To-Dos

1. ~~OAuth / On-Behalf-Of Authentication (Web)~~ ✅
   - Databricks Apps handles authentication automatically for web deployment
   - User context extracted from forwarded headers (X-Forwarded-User, X-Forwarded-Access-Token, etc.)

2. PDF Widget — Basic Flow

 Build PDF upload widget in Flutter (file_picker or drag-and-drop)
 Backend endpoint to receive PDF and extract text (pymupdf/pdfplumber)
 Detect page count and route accordingly:

≤3 pages → pass text directly to LLM context
>3 pages → trigger RAG pipeline



3. PDF Widget — RAG Pipeline (>3 pages)

 Chunking logic (semantic or fixed-size with overlap)
 Embedding endpoint (Databricks Model Serving or external)
 Postgres + pgvector setup (if not already running)
 Store chunks with embeddings, tagged by document ID and user
 Retrieval: embed query → similarity search → return top-k chunks
 Cache/hash uploaded PDFs to skip re-indexing duplicates

4. TTS File Storage — User-Scoped Volumes

 Generate TTS audio files (existing or new endpoint)
 Write files to Databricks Volumes under user-specific path (e.g., /Volumes/catalog/schema/tts_audio/{user_id}/)
 Apply Unity Catalog permissions so each user can only access their own files
 Backend endpoint to list user's available TTS files


---

## Back Burner

### OAuth / On-Behalf-Of Authentication (Mobile/Desktop)
- Implement OAuth 2.0 flow in Flutter (PKCE for mobile/desktop)
- Configure Databricks as identity provider or integrate with your IdP (Azure AD, Okta, etc.)
- Backend: Validate tokens and extract user identity on every request
- Propagate user context to downstream Databricks API calls (Unity Catalog, Model Serving, Volumes)
- Handle token refresh silently in the Flutter client
