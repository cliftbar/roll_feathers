import { Page } from '@playwright/test';

/**
 * Flutter web requires clicking the accessibility placeholder before the
 * semantic tree is exposed to Playwright. Call this once after every
 * page.goto() / page.reload().
 */
export async function enableA11y(page: Page): Promise<void> {
  // The placeholder is off-screen, so Playwright's .click() is rejected.
  // Wait for it to be in the DOM (it appears after Flutter initialises), then
  // fire a JS click so the viewport check is bypassed.
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 10000 });
  await page.evaluate(() => {
    (document.querySelector('flt-semantics-placeholder') as HTMLElement | null)?.click();
  });
  // Wait until interactive semantic nodes appear — confirms the full tree is
  // built, not just the placeholder being cleared.
  await page.waitForFunction(
    () => document.querySelectorAll('flt-semantics[role="button"]').length > 0,
    { timeout: 10000 },
  ).catch(() => {});
}

/**
 * Inject dddice room config directly into localStorage so the app picks it
 * up on next reload. Values must be JSON-encoded (the app uses raw keys
 * without a flutter. prefix, and stores JSON strings for string fields).
 */
export async function injectDddiceRoomConfig(
  page: Page,
  roomSlug: string,
  roomName: string,
): Promise<void> {
  await page.evaluate(
    ([slug, name]) => {
      localStorage.setItem('dddice_room_slug', JSON.stringify(slug));
      localStorage.setItem('dddice_room_name', JSON.stringify(name));
    },
    [roomSlug, roomName],
  );
}

/** Read all dddice-related localStorage keys. */
export async function readDddiceConfig(
  page: Page,
): Promise<Record<string, string | null>> {
  return page.evaluate(() => {
    const keys = [
      'dddice_enabled',
      'dddice_token',
      'dddice_is_guest',
      'dddice_needs_reauth',
      'dddice_room_slug',
      'dddice_room_name',
      'dddice_theme_id',
      'dddice_theme_name',
    ];
    return Object.fromEntries(keys.map(k => [k, localStorage.getItem(k)]));
  });
}

/** Open the nav drawer and click a named settings button. */
export async function openSettingsItem(page: Page, name: string | RegExp): Promise<void> {
  await page.getByRole('button', { name: 'Open navigation menu' }).click();
  await page.getByRole('button', { name }).click();
}

/** Add a virtual die via the "Add Die" dialog. */
export async function addVirtualDie(
  page: Page,
  dieName: string,
  faces: number,
): Promise<void> {
  await page.getByRole('button', { name: 'Add Die' }).click();
  await page.getByRole('textbox', { name: 'Die Name' }).fill(dieName);
  await page.getByRole('textbox', { name: 'Number of Faces' }).fill(String(faces));
  await page.getByRole('button', { name: 'Add' }).click();
}

/** Roll all dice and wait for the history to update. */
export async function roll(page: Page): Promise<void> {
  // exact:true prevents matching die cards whose accessible name contains "rolling"
  await page.getByRole('button', { name: 'Roll', exact: true }).click();
  await page.waitForTimeout(300);
}
