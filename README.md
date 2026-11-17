# Lenovo TB311FU local manifest

This repository hosts the LineageOS local manifest for the Lenovo TB311FU.

## HTTP endpoints

- `/` provides a small landing page.
- `/TB311FU.xml` serves the manifest as XML.
- `/health` returns a JSON health response for Railway.

## Deploy on Railway

Create a Railway service from this repository and build from the repository root. Railpack detects the Node.js app from `package.json` and starts it with `npm start`. The server listens on Railway's `PORT` variable.

In the Railway service settings, set the healthcheck path to `/health`. Under Networking, generate a Railway domain to make the endpoints public.
