import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/tasks': {
        target: 'http://localhost:5223',
        changeOrigin: true,
      },
    },
  },
});
