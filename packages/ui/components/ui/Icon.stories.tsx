import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { Icon, type IconName } from './Icon'

const meta: Meta<typeof Icon> = {
  title: 'Brand/Icons',
  component: Icon,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof Icon>

const allIcons: IconName[] = [
  'check',
  'x-circle',
  'alert-triangle',
  'clock',
  'refresh-cw',
  'terminal',
  'mail',
  'chevron-right',
]

export const Single: Story = { args: { name: 'check', size: 24 } }

export const AllIcons: Story = {
  render: () => (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16 }}>
      {allIcons.map((name) => (
        <div key={name} style={{ textAlign: 'center' }}>
          <Icon name={name} size={28} />
          <div style={{ fontSize: 12, color: 'var(--foreground-secondary)', marginTop: 4 }}>{name}</div>
        </div>
      ))}
    </div>
  ),
}
