import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{vue,ts,js}'],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: '#0b0b0f',
          accent: '#10b981',
        },
      },
    },
  },
  plugins: [],
} satisfies Config;