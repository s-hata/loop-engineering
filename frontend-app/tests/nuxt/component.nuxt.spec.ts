import { mountSuspended } from '@nuxt/test-utils/runtime'
import { describe, expect, it } from 'vitest'

import { Button } from '~/components/ui/button'

describe('Button', () => {
  it('renders inside the Nuxt runtime', async () => {
    const wrapper = await mountSuspended(Button, {
      slots: { default: 'Example' },
    })

    expect(wrapper.text()).toBe('Example')
  })
})
