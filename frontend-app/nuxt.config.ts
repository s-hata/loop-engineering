import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  devtools: { enabled: false },
  app: {
    head: {
      title: 'Frontend App',
    },
  },
  css: ['~/assets/css/tailwind.css'],
  components: [{ path: '~/components', extensions: ['vue'] }],
  vite: {
    plugins: [tailwindcss()],
  },
  typescript: {
    strict: true,
    typeCheck: false,
  },
})
