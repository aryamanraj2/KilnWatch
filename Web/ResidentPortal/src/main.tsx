import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { LocaleProvider } from './i18n';
import { StoreProvider } from './app/state';
import { App } from './app/App';
import './styles/global.css';

createRoot(document.getElementById('root')!).render(<StrictMode><BrowserRouter><LocaleProvider><StoreProvider><App /></StoreProvider></LocaleProvider></BrowserRouter></StrictMode>);
