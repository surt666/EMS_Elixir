// @ts-check
import { defineConfig } from "astro/config";

import alpinejs from "@astrojs/alpinejs";
import react from "@astrojs/react";
import htmx from "astro-htmx";
import hyperscript from "astro-hyperscript";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  integrations: [alpinejs(), react(), htmx(), hyperscript()],
  image: {
    service: { entrypoint: 'astro/assets/services/noop' }
  },
  output: 'static',
  vite: {
    server: {
      headers: {
        'Content-Security-Policy': [
          "default-src 'self'",
          "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://*.quicksight.aws.amazon.com https://*.amazonaws.com https://esm.sh",
          "style-src 'self' 'unsafe-inline' https://*.quicksight.aws.amazon.com",
          "img-src 'self' data: blob: https://*.quicksight.aws.amazon.com https://*.amazonaws.com",
          "font-src 'self' data: https://*.quicksight.aws.amazon.com",
          "connect-src 'self' https://*.quicksight.aws.amazon.com https://*.amazonaws.com wss://*.quicksight.aws.amazon.com https://d368wcanc53tdl.cloudfront.net blob:",
          "frame-src 'self' https://*.quicksight.aws.amazon.com",
          "worker-src 'self' blob:",
          "child-src 'self' blob:"
        ].join('; ')
      },
      proxy: {
        '/hierarchy': {
          target: 'http://localhost:4000',
          changeOrigin: true,
          secure: false,
        },
        '/api': {
          target: 'http://localhost:4000',
          changeOrigin: true,
          secure: false,
        },
        '/aggregations': {
          target: 'http://localhost:4000',
          changeOrigin: true,
          secure: false,
        },
      }
    },
    plugins: [tailwindcss()],
  },
});
