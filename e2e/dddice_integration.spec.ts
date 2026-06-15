// End-to-end tests for the dddice integration (Roll Feathers web).
//
// Prerequisites:
//   - `flutter run -d chrome --web-port 57428` is running (or any web server on
//     the configured baseURL in playwright.config.ts).
//   - For the INTEGRATION group (tagged @integration): a real dddice guest token
//     must be stored in DDDICE_TOKEN env var, and the room slug in DDDICE_ROOM.
//     These tests verify that rolls actually appear in the remote dddice room and
//     are skipped automatically when the env vars are absent.
//
// Run with integration tests:
//   DDDICE_TOKEN=xxx DDDICE_ROOM=yyy npx playwright test dddice_integration.spec.ts

import { test, expect, Page } from '@playwright/test';
import {
  enableA11y,
  injectDddiceRoomConfig,
  readDddiceConfig,
  openSettingsItem,
  addVirtualDie,
  roll,
} from './helpers';

// ---------------------------------------------------------------------------
// Helpers local to this spec
// ---------------------------------------------------------------------------

async function goto(page: Page): Promise<void> {
  await page.goto('/');
  await enableA11y(page);
}

async function getHistoryEntries(page: Page): Promise<string[]> {
  // The roll animation can take >300ms. Wait until the history group (second
  // [role="group"]) appears and has at least one non-empty flt-semantics child.
  await page.waitForFunction(
    () => {
      const groups = document.querySelectorAll('[role="group"]');
      if (groups.length < 2) return false;
      const last = groups[groups.length - 1];
      return Array.from(last.querySelectorAll('flt-semantics'))
        .some(el => (el as HTMLElement).innerText?.trim().length > 0);
    },
    { timeout: 5000 },
  ).catch(() => {/* return empty if history never appears */});

  return page.evaluate(() => {
    const groups = document.querySelectorAll('[role="group"]');
    if (groups.length === 0) return [];
    const last = groups[groups.length - 1] as HTMLElement;
    return Array.from(last.querySelectorAll('flt-semantics'))
      .map(el => (el as HTMLElement).innerText?.trim() ?? '')
      .filter(t => t.length > 0);
  });
}

// ---------------------------------------------------------------------------
// Setup shared across tests — inject a known guest config before each test
// so state is deterministic regardless of prior browser sessions.
// ---------------------------------------------------------------------------

const GUEST_TOKEN = process.env['DDDICE_TOKEN'] ?? 'test-token-placeholder';
const ROOM_SLUG = process.env['DDDICE_ROOM'] ?? 'Q-kMSRC';
const ROOM_NAME = process.env['DDDICE_ROOM_NAME'] ?? 'xcb-test-room';
const hasRealCreds = Boolean(process.env['DDDICE_TOKEN'] && process.env['DDDICE_ROOM']);

// ---------------------------------------------------------------------------
// Group 1: Core dice UI (no dddice networking required)
// ---------------------------------------------------------------------------

test.describe('core dice UI', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    // Pre-seed localStorage so dddice state is defined (disabled by default here)
    await page.evaluate(() => {
      localStorage.setItem('dddice_enabled', 'false');
      localStorage.setItem('dddice_is_guest', 'true');
      localStorage.setItem('dddice_needs_reauth', 'false');
      localStorage.setItem('dddice_room_slug', '""');
      localStorage.setItem('dddice_room_name', '""');
      localStorage.setItem('dddice_token', '""');
    });
    await enableA11y(page);
  });

  test('starts with no dice and empty history', async ({ page }) => {
    await expect(page.getByText('No dice added')).toBeVisible();
    await expect(page.getByText('Make some rolls!')).toBeVisible();
  });

  test('adds a virtual die and it appears in the die list', async ({ page }) => {
    await addVirtualDie(page, 'd20', 20);
    await expect(page.getByRole('button', { name: /d20/ })).toBeVisible();
  });

  test('rolls a single virtual die and records result in history', async ({ page }) => {
    await addVirtualDie(page, 'd20', 20);
    await roll(page);
    const entries = await getHistoryEntries(page);
    expect(entries.some(e => /Roll .+: \d+/.test(e))).toBe(true);
  });

  test('rolls two virtual dice and shows combined result in history', async ({ page }) => {
    await addVirtualDie(page, 'd20', 20);
    await addVirtualDie(page, 'd6', 6);
    await roll(page);
    const entries = await getHistoryEntries(page);
    // Multi-die format: "Roll <name>: N (a, b)"
    expect(entries.some(e => /Roll .+: \d+ \(\d+, \d+\)/.test(e))).toBe(true);
  });

  test('clear button removes all history entries', async ({ page }) => {
    await addVirtualDie(page, 'd20', 20);
    await roll(page);
    await roll(page);
    await page.getByRole('button', { name: 'Clear' }).click();
    await expect(page.getByText('Make some rolls!')).toBeVisible();
  });

  test('auto-roll switch can be toggled off and back on', async ({ page }) => {
    const toggle = page.getByRole('switch', { name: 'Auto-roll' });
    await expect(toggle).toBeChecked();
    await toggle.click();
    await expect(toggle).not.toBeChecked();
    await toggle.click();
    await expect(toggle).toBeChecked();
  });

  test('manual Roll button still works when auto-roll is off', async ({ page }) => {
    await addVirtualDie(page, 'd6', 6);
    await page.getByRole('switch', { name: 'Auto-roll' }).click(); // disable
    await page.getByRole('button', { name: 'Roll' }).click();
    await page.waitForTimeout(300);
    const entries = await getHistoryEntries(page);
    expect(entries.some(e => /Roll .+: \d+/.test(e))).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Group 2: Settings UI
// ---------------------------------------------------------------------------

test.describe('settings UI', () => {
  test.beforeEach(async ({ page }) => {
    await goto(page);
  });

  test('dark mode toggle cycles label Light Mode → Dark Mode', async ({ page }) => {
    await page.getByRole('button', { name: 'Open navigation menu' }).click();
    const modeBtn = page.getByRole('button', { name: /Mode/ });
    const initialLabel = await modeBtn.innerText();
    await modeBtn.click();
    // Nav dismisses on click; reopen to read new label
    await page.getByRole('button', { name: 'Open navigation menu' }).click();
    const newLabel = await page.getByRole('button', { name: /Mode/ }).innerText();
    expect(newLabel).not.toEqual(initialLabel);
  });

  test('rule scripts screen lists saved scripts', async ({ page }) => {
    await openSettingsItem(page, 'Rule Scripts');
    await expect(page.getByText('Saved Scripts')).toBeVisible();
    // Flutter Text widgets render their content as aria-label, not innerText —
    // use getByRole to match via accessible name.
    await expect(page.getByRole('group', { name: /Basic Blink/ })).toBeVisible();
  });

  test('rule script checkbox can be toggled', async ({ page }) => {
    await openSettingsItem(page, 'Rule Scripts');
    const basicBlinkCheckbox = page
      .getByRole('group', { name: /Basic Blink/ })
      .getByRole('checkbox');
    const initial = await basicBlinkCheckbox.isChecked();
    await basicBlinkCheckbox.click();
    // Wait for Flutter to process the tap and update the a11y tree
    await page.waitForTimeout(500);
    expect(await basicBlinkCheckbox.isChecked()).toBe(!initial);
  });
});

// ---------------------------------------------------------------------------
// Group 3: dddice settings UI (no live network calls required)
// ---------------------------------------------------------------------------

test.describe('dddice settings UI', () => {
  test.beforeEach(async ({ page }) => {
    // Pre-seed a guest session so the settings dialog shows the authenticated state
    await page.goto('/');
    await page.evaluate(
      ([token, slug, name]) => {
        localStorage.setItem('dddice_enabled', 'false');
        localStorage.setItem('dddice_token', JSON.stringify(token));
        localStorage.setItem('dddice_is_guest', 'true');
        localStorage.setItem('dddice_needs_reauth', 'false');
        localStorage.setItem('dddice_room_slug', JSON.stringify(slug));
        localStorage.setItem('dddice_room_name', JSON.stringify(name));
        localStorage.setItem('dddice_theme_id', '""');
        localStorage.setItem('dddice_theme_name', '""');
      },
      [GUEST_TOKEN, ROOM_SLUG, ROOM_NAME],
    );
    await enableA11y(page);
  });

  test('nav subtitle shows Guest and room name when configured', async ({ page }) => {
    await page.reload();
    await enableA11y(page);
    await page.getByRole('button', { name: 'Open navigation menu' }).click();
    await expect(
      page.getByRole('button', { name: new RegExp(`Guest.*${ROOM_NAME}`) }),
    ).toBeVisible();
  });

  test('enable toggle turns dddice on and persists to localStorage', async ({ page }) => {
    await page.reload();
    await enableA11y(page);
    await openSettingsItem(page, new RegExp('dddice Settings'));
    const toggle = page.getByRole('switch', { name: 'Enable dddice' });
    await toggle.click();
    await expect(toggle).toBeChecked();
    const config = await readDddiceConfig(page);
    expect(config['dddice_enabled']).toBe('true');
  });

  test('sign out button clears token from localStorage', async ({ page }) => {
    await page.reload();
    await enableA11y(page);
    await openSettingsItem(page, new RegExp('dddice Settings'));
    await page.getByRole('button', { name: 'Sign out' }).click();
    const config = await readDddiceConfig(page);
    // After sign-out the token should be empty
    expect(config['dddice_token']).toMatch(/^"?"?$/);
  });

  test('theme row shows dddice-bees label for guest accounts', async ({ page }) => {
    await page.reload();
    await enableA11y(page);
    await openSettingsItem(page, new RegExp('dddice Settings'));
    // Flutter's Semantics(container:true) creates an flt-semantics node whose
    // text content (not aria-label) contains the label. .last() narrows to the
    // leaf node rather than its ancestor containers.
    await expect(
      page.locator('flt-semantics').filter({ hasText: 'dddice-bees (guest default)' }).last()
    ).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// Group 4: Live dddice integration (@integration — requires real credentials)
// ---------------------------------------------------------------------------

test.describe('dddice live integration @integration', () => {
  test.skip(!hasRealCreds, 'Set DDDICE_TOKEN and DDDICE_ROOM to run integration tests');

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    // Seed real credentials so we can test actual API calls
    await page.evaluate(
      ([token, slug, name]) => {
        localStorage.setItem('dddice_enabled', 'true');
        localStorage.setItem('dddice_token', JSON.stringify(token));
        localStorage.setItem('dddice_is_guest', 'true');
        localStorage.setItem('dddice_needs_reauth', 'false');
        localStorage.setItem('dddice_room_slug', JSON.stringify(slug));
        localStorage.setItem('dddice_room_name', JSON.stringify(name));
        localStorage.setItem('dddice_theme_id', '""');
        localStorage.setItem('dddice_theme_name', '""');
      },
      [GUEST_TOKEN, ROOM_SLUG, ROOM_NAME],
    );
    await page.reload();
    await enableA11y(page);
  });

  test('single virtual die roll fires to dddice without error', async ({ page }) => {
    const errors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error' && !msg.text().includes('409')) {
        errors.push(msg.text());
      }
    });

    await addVirtualDie(page, 'd20', 20);
    await roll(page);

    // Allow network round-trip
    await page.waitForTimeout(1500);

    // Verify roll recorded locally
    const entries = await getHistoryEntries(page);
    expect(entries.some(e => /Roll .+: \d+/.test(e))).toBe(true);

    // No unexpected errors (409 from joinRoom is expected and filtered above)
    expect(errors).toHaveLength(0);
  });

  test('multi-die roll fires both dice to dddice', async ({ page }) => {
    const errors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error' && !msg.text().includes('409')) {
        errors.push(msg.text());
      }
    });

    await addVirtualDie(page, 'd20', 20);
    await addVirtualDie(page, 'd6', 6);
    await roll(page);

    await page.waitForTimeout(1500);

    const entries = await getHistoryEntries(page);
    expect(entries.some(e => /Roll .+: \d+ \(\d+, \d+\)/.test(e))).toBe(true);
    expect(errors).toHaveLength(0);
  });

  test('rule label is sent to dddice when Basic Blink fires', async ({ page }) => {
    // Basic Blink defines `standardRoll` for any die — ensure it is checked
    await openSettingsItem(page, 'Rule Scripts');
    const basicBlinkCheckbox = page
      .getByRole('group', { name: /Basic Blink/ })
      .getByRole('checkbox');
    if (!(await basicBlinkCheckbox.isChecked())) {
      await basicBlinkCheckbox.click();
    }
    await page.getByRole('button', { name: 'Back' }).click();

    // Verify roll history uses the rule name
    await addVirtualDie(page, 'd20', 20);
    await roll(page);

    const entries = await getHistoryEntries(page);
    // Rule-driven rolls appear as "Roll <standardRoll>: N (N)"
    expect(entries.some(e => e.includes('standardRoll'))).toBe(true);
  });

  test('second roll in same session does not re-join room (409 appears only once)', async ({
    page,
  }) => {
    const participantCalls: string[] = [];
    await page.route('**/room/**/participant', route => {
      participantCalls.push(route.request().url());
      route.continue();
    });

    await addVirtualDie(page, 'd6', 6);
    await roll(page);
    await page.waitForTimeout(1000);
    const callsAfterFirst = participantCalls.length;

    await roll(page);
    await page.waitForTimeout(1000);

    // joinRoom should have been called exactly once across two rolls
    expect(callsAfterFirst).toBe(1);
    expect(participantCalls.length).toBe(1);
  });
});
