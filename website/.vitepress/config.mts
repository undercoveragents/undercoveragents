import { defineConfig } from "vitepress";

const githubUrl = "https://github.com/undercoveragents/undercoveragents";

export default defineConfig({
  title: "Undercover Agents",
  description:
    "Open source AI operations for teams that need agents, missions, tools, RAG, skills, chat, and observability in one Rails-native control plane.",
  lang: "en-US",
  cleanUrls: true,
  lastUpdated: true,
  appearance: false,
  ignoreDeadLinks: true,
  markdown: {
    theme: {
      light: "github-dark",
      dark: "github-dark",
    },
  },
  head: [
    ["meta", { name: "theme-color", content: "#090d17" }],
    ["meta", { name: "color-scheme", content: "dark" }],
    ["link", { rel: "icon", type: "image/svg+xml", href: "/favicon-agent.svg" }],
    ["link", { rel: "icon", href: "/icon.png" }],
    [
      "link",
      {
        rel: "stylesheet",
        href: "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css",
      },
    ],
    ["link", { rel: "preconnect", href: "https://fonts.googleapis.com" }],
    ["link", { rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: "" }],
    [
      "link",
      {
        rel: "stylesheet",
        href:
          "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600;700&family=Space+Grotesk:wght@500;700&display=swap",
      },
    ],
    [
      "script",
      {},
      "document.documentElement.classList.add('dark');document.documentElement.style.colorScheme='dark';",
    ],
  ],
  themeConfig: {
    logo: "/logo-header.png",
    siteTitle: "Undercover Agents",
    nav: [
      { text: "Overview", link: "/#overview" },
      { text: "Main Features", link: "/#main-features" },
      { text: "Guide", link: "/guide/getting-started" },
      { text: "GitHub", link: githubUrl },
    ],
    sidebar: {
      "/guide/": [
        {
          text: "Guide",
          items: [
            { text: "Overview", link: "/guide/getting-started" },
            { text: "Agents", link: "/guide/agents" },
            { text: "Tools", link: "/guide/tools" },
            { text: "Missions", link: "/guide/missions" },
          ],
        },
      ],
    },
    socialLinks: [{ icon: "github", link: githubUrl }],
    search: {
      provider: "local",
    },
    footer: {
      message: "Open source AI platform built with Ruby on Rails by Mirko Mignini. For information: <a href=\"mailto:info@undercoveragents.ai\">info@undercoveragents.ai</a>",
      copyright: "Copyright © 2026 Undercover Agents",
    },
  },
});
