export default function Home() {
  return (
    <div style={{ padding: 32, fontFamily: 'var(--font-family-sans)' }}>
      <img src="/assets/logo-full.svg" alt="RelayGate Ops" height={40} />
      <p style={{ marginTop: 16 }}>
        このプロジェクトは Storybook のトークン/コンポーネントホスト用です。
        <code>npm run storybook</code> で確認してください。
      </p>
    </div>
  )
}
