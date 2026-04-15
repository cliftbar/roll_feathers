# Per-PR Web Previews with GitHub CI

To enable per-pull request web previews for the Roll Feathers project, follow these requirements and steps.

## Requirements

1.  **Hosting Provider**: A service that supports dynamic preview URLs for pull requests.
    -   **Firebase Hosting**: Natively supports GitHub Actions for PR previews.
    -   **Cloudflare Pages**: Very fast and easy integration with GitHub.
    -   **Surge.sh**: Simple and can be used with a custom domain.

2.  **GitHub Workflow**: A new GitHub Actions file (e.g., `.github/workflows/web-preview.yml`) to build and deploy.

3.  **Authentication**: API tokens/secrets added to GitHub Repository Secrets.

## Recommended Approach: Firebase Hosting

Firebase Hosting is highly recommended because it provides automatic PR comments with the preview URL.

### 1. Project Setup
-   Initialize Firebase in the project: `firebase init hosting`
-   Select/Create a Firebase project.
-   Set `build/web` as the public directory.
-   Configure as a single-page app: Yes.

### 2. GitHub Actions
Add a workflow file that triggers on `pull_request`:

```yaml
name: Deploy Web Preview
on: [pull_request]

jobs:
  build_and_preview:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version-file: pubspec.yaml
      - run: flutter pub get
      - run: flutter build web --pwa-strategy=none
      - uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: ${{ secrets.GITHUB_TOKEN }}
          firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_ROLL_FEATHERS }}
          projectId: roll-feathers
```

### 3. Repository Secrets
-   Generate a Firebase Service Account JSON and add it to GitHub Secrets as `FIREBASE_SERVICE_ACCOUNT_ROLL_FEATHERS`.

## Alternative: Cloudflare Pages

Cloudflare Pages can also be used. You can either:
-   Connect the GitHub repo directly in the Cloudflare dashboard.
-   Use GitHub Actions to build and then upload using `cloudflare/pages-action`.

### Why not use the current private server (goose.hive)?
While possible, it would require:
-   Configuring a reverse proxy for dynamic subdomains (e.g., `pr-123.rollfeathers.ungawatkt.com`).
-   Setting up SSH keys in GitHub CI for the `goose.hive` user.
-   Managing the cleanup of old PR preview builds on the server.
Cloud services handle all of this automatically.
