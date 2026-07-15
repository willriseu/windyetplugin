import type { ExternalPluginConfig } from '@windy/interfaces';

const config: ExternalPluginConfig = {
    name: 'windy-plugin-zanka-camp-watch',
    version: '0.6.3',
    icon: '⛺',
    title: 'Zánka táborfigyelő',
    description: 'Balatoni viharjelzés, tűzgyújtási tilalom és tábori figyelmeztetések.',
    author: 'Zánkai Erzsébet-tábor',
    repository: 'https://github.com/windycom/windy-plugin-template',
    desktopUI: 'embedded',
    mobileUI: 'fullscreen',
    routerPath: '/zanka-camp-watch',
    private: true,
};

export default config;
