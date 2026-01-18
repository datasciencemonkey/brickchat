BrickChat UI — Feature To-Dos

1. The clip showing uploads vanishes. we should be able to retain it for the follow up multi-turn conversations
   a. ensure that when we go back to threads, it still shows the same "uploaded chip", this needs to be reconstructured based on what is in the postgres table- we should capture the name of the file as a part of the metadata.

2. When a file upload button is clicked check to see if an existing conversation with message length >=2. if so, open a new thread with a small modal that reads "starting new conversation"...


Future to-dos
1. Support image uploads
2. Support interaction with image models
3. Enable MCP servers

---

## Back Burner

### OAuth / On-Behalf-Of Authentication (Mobile/Desktop)
- Implement OAuth 2.0 flow in Flutter (PKCE for mobile/desktop)
- Configure Databricks as identity provider or integrate with your IdP (Azure AD, Okta, etc.)
- Backend: Validate tokens and extract user identity on every request
- Propagate user context to downstream Databricks API calls (Unity Catalog, Model Serving, Volumes)
- Handle token refresh silently in the Flutter client


