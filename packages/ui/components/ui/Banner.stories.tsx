import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { Banner } from './Banner'

const meta: Meta<typeof Banner> = {
  title: 'UI/Banner',
  component: Banner,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof Banner>

export const Info: Story = { args: { variant: 'info', title: 'blue slot を起動しました', children: 'run_id=run-20260817-001' } }
export const Success: Story = { args: { variant: 'success', title: '確報クロスチェックが正常終了しました', children: '全テーブル・全ファイルの整合性を確認しました' } }
export const Warning: Story = { args: { variant: 'warning', title: 'ハング疑いを検知しました', children: 'background実行がしきい値(30分)を超過しています' } }
export const Error: Story = { args: { variant: 'error', title: '速報クロスチェックが異常終了しました', children: 'exitcode=1 差分検知のため確認が必要です' } }
