import { h } from "vue";
import DefaultTheme from "vitepress/theme";
import MarketingHeroActions from "./components/MarketingHeroActions.vue";
import MarketingSections from "./components/MarketingSections.vue";

import "./custom.css";

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      "home-hero-info-after": () => h(MarketingHeroActions),
    });
  },
  enhanceApp({ app }) {
    app.component("MarketingSections", MarketingSections);
  },
};
