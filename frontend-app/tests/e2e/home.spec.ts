import { expect, test } from '@nuxt/test-utils/playwright'

test('home page is available', async ({ page, goto }) => {
  await goto('/', { waitUntil: 'hydration' })

  await expect(page).toHaveTitle('Frontend App')
  await expect(page.getByRole('heading', { name: 'Nuxt is ready.' })).toBeVisible()
})
