import { defineConfig } from "vitepress";

// https://vitepress.dev/reference/site-config
export default defineConfig({
	title: "Jexplorer",
	base: "/Jexplorer/",
	description: "A VitePress Site",
	themeConfig: {
		// https://vitepress.dev/reference/default-theme-config
		nav: [
			{ text: "API", link: "/api/setting_editor.md" },
		],

		sidebar: {
			"/api/": [
				{
					text: "Namespaces",
					items: [
						{ text: "Setting Editor", link: "/api/setting_editor.md" },
					],
				},
			],
		}
	},
});
