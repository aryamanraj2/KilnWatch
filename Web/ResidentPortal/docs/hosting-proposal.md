# AWS Amplify hosting proposal — not activated

Intended hosting remains AWS Amplify. No Site was registered, no infrastructure was changed, and no deployment or automatic-build connection was made.

The AWS teammate should review the following monorepo build configuration after the runtime/contract decisions are final. It assumes the repository root is the Amplify build root and the app root is `Web/ResidentPortal`:

```yaml
version: 1
applications:
  - appRoot: Web/ResidentPortal
    frontend:
      phases:
        preBuild:
          commands:
            - nvm install 24.21.0
            - nvm use 24.21.0
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: dist
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
```

Set the Amplify monorepo app-root variable consistently. Confirm runtime availability in the actual build image rather than assuming the local runtime exists there. Keep the lockfile install and the app-local `dist` directory; never publish the repository root, `.runtime`, `.cache`, tests, private `.local` data, or model artifacts.

Preview environments should explicitly set `VITE_DATA_MODE=fixture`. Only an authorized R2/R4 production environment receives the approved public API prefix and exact image-host list. No inspector token, AWS key, secret, or private endpoint belongs in Vite variables. The current R1 HTML uses `noindex,nofollow`; keep prototypes out of indexing and revisit public record metadata only after publication approval.

Configure SPA rewrites only for actual frontend routes (`/`, `/area`, `/kilns/<id>`, `/rules/<id>`, `/complaint`, `/about`, `/privacy`). Missing `/assets/*.js`, styles, and images must remain 404s; a broad HTML fallback for missing JavaScript is incorrect. Verify direct-link refresh and missing assets on the hosted environment.

Proposed production header policy, to be reviewed against actual origins: HTTPS/HSTS after domain validation, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, restrictive `frame-ancestors`, and a CSP covering self-hosted scripts/styles, approved `connect-src`/`img-src`, and no object embedding. Current React style attributes for the map/comparator need an explicit compatible style policy. Do not declare a CSP that breaks these controls or simply allow every origin. No remote fonts or workers are used in R1; later MapLibre sources/worker policy require review. Geolocation should be limited to the site's own secure context.

Source maps are disabled in the local production build. Test source-map and caching behavior against actual hosted responses. Personal locations, drafts, and complaint content must never enter deployment metadata, page URLs, analytics, or server logs beyond the deliberately agreed public search request.

R4 proof: hosted HTTPS, direct links/refresh, correct asset MIME/404 behavior, anonymous publication boundary, real API/evidence loading, exact origins/headers, opt-in location, both-language exports, and incremental cost/quotas. A hosted fixture preview does not prove a released public registry or live resident assistant.

References for the AWS teammate: [Amplify monorepos](https://docs.aws.amazon.com/amplify/latest/userguide/monorepo-configuration.html), [rewrites](https://docs.aws.amazon.com/amplify/latest/userguide/redirects.html), [headers](https://docs.aws.amazon.com/amplify/latest/userguide/custom-headers.html). This proposal has not been deployed or validated against an Amplify build image.
