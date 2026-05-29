import { Configuration, LogLevel } from '@azure/msal-browser';

// Runtime config injected by entrypoint.sh in production, falls back to Vite env vars for local dev.
const runtimeConfig = (window as unknown as { __CONFIG__?: Record<string, string> }).__CONFIG__ ?? {};

function getConfig(key: string): string {
  return runtimeConfig[key] || import.meta.env[key] || '';
}

export const msalConfig: Configuration = {
  auth: {
    clientId: getConfig('VITE_ENTRA_CLIENT_ID'),
    authority: `https://login.microsoftonline.com/${getConfig('VITE_ENTRA_TENANT_ID') || 'common'}`,
    redirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: 'localStorage',
  },
  system: {
    loggerOptions: {
      logLevel: LogLevel.Warning,
    },
  },
};

export const tasksApiScope = getConfig('VITE_TASKS_API_SCOPE') || 'api://<tasks-api-app-id>/Tasks.ReadWrite';

export const loginRequest = {
  scopes: [tasksApiScope],
};
