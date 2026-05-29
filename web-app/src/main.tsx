import React from 'react';
import ReactDOM from 'react-dom/client';
import { FluentProvider, webLightTheme } from '@fluentui/react-components';
import { PublicClientApplication } from '@azure/msal-browser';
import { MsalProvider } from '@azure/msal-react';
import { msalConfig } from './auth/authConfig';
import App from './App';

const msalInstance = new PublicClientApplication(msalConfig);

msalInstance.initialize().then(() => {
  // Process any auth response (popup or redirect) BEFORE rendering.
  // In a popup window this extracts the token, posts it to the parent, and closes the popup.
  return msalInstance.handleRedirectPromise();
}).then(() => {
  ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
      <MsalProvider instance={msalInstance}>
        <FluentProvider theme={webLightTheme}>
          <App />
        </FluentProvider>
      </MsalProvider>
    </React.StrictMode>
  );
});
