export const PALETTE = ["#ff6b9d", "#5ce1e6", "#ffd166", "#b28dff", "#7cf29c"];

/** テーマごとの弾の色と背景色(アプリの Skin と同じ値) */
export const THEME_PALETTES: Record<string, { bullets: string[]; background: string }> = {
  sakura: { bullets: ["#ff8fb8", "#ffc4dd", "#ff5c8a", "#ffb38a", "#f2e6ff"], background: "#1a0a14" },
  ocean: { bullets: ["#3dd6d0", "#5aa9ff", "#9fe8ff", "#2f6fe0", "#7cf2c8"], background: "#04101f" },
  aurora: { bullets: ["#7cf29c", "#b28dff", "#5ce1e6", "#e8ff7a", "#ff8ae2"], background: "#07120f" },
};
