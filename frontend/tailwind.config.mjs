/** @type {import('tailwindcss').Config} */
export default {
	content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}', '../crates/query/src/**/*.{rs, html}'],
	theme: {
		extend: {
			backgroundImage: {
				'accent-gradient': 'linear-gradient(45deg, rgb(136, 58, 234), rgb(224, 204, 250) 30%, white 60%)',
			},
			backgroundSize: {
				'400%': '400%',
			},
		},
	},
	plugins: [
		function({ addUtilities }) {
			addUtilities({
				'.text-gradient': {
					'background-image': 'var(--accent-gradient)',
					'-webkit-background-clip': 'text',
					'-webkit-text-fill-color': 'transparent',
					'background-size': '400%',
					'background-position': '0%',
				},
			});
		},
	],
}
