# Intelligence configuration

The backend has no reachable configuration UI. Add an Intelligence Settings tab.
- Add MeetingIntelligence package dependency to FeatureSettings.
- Add shared secure field using control surface, field radius, body type, 32 pt height.
- Add three cards: Keychain connection/test, persisted defaults, custom instructions.
- Expose tab in Settings/search; remove inaccurate local-only Settings subtitle.
- Verify FeatureSettings compilation and focused checks. Native visual inspection remains required.
Tokens: Tok.control/text/text2; Space.xs/sm/lg; Radius.field; ControlHeight.large; AppType.body/label; shared SettingRow/Card/Segmented/Dropdown/AppToggle/AppTextEditor/AppButton. Existing semantic key/keyboard/eye and meeting symbols.
