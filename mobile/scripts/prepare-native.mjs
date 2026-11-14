import { access, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const platform = process.argv[2];
if (!['android', 'ios'].includes(platform)) {
  throw new Error('Usage: node scripts/prepare-native.mjs android|ios');
}

async function exists(path) {
  try { await access(path); return true; } catch { return false; }
}

if (platform === 'android') {
  const stringsPath = resolve('android/app/src/main/res/values/strings.xml');
  const manifestPath = resolve('android/app/src/main/AndroidManifest.xml');

  if (await exists(stringsPath)) {
    let xml = await readFile(stringsPath, 'utf8');
    const label = 'عَمِّر | AMMIR';
    if (/<string name="app_name">[\s\S]*?<\/string>/.test(xml)) {
      xml = xml.replace(/<string name="app_name">[\s\S]*?<\/string>/, '<string name="app_name">' + label + '</string>');
    } else {
      xml = xml.replace('</resources>', '    <string name="app_name">' + label + '</string>\n</resources>');
    }
    await writeFile(stringsPath, xml, 'utf8');
  }

  if (await exists(manifestPath)) {
    let xml = await readFile(manifestPath, 'utf8');
    xml = xml.replace(
      /(<activity\b[^>]*android:name="\.MainActivity"[^>]*)(>)/,
      (match, opening, end) => opening.includes('android:windowSoftInputMode')
        ? match
        : opening + ' android:windowSoftInputMode="adjustResize"' + end
    );
    await writeFile(manifestPath, xml, 'utf8');
  }
}

if (platform === 'ios') {
  const plistPath = resolve('ios/App/App/Info.plist');
  if (!(await exists(plistPath))) throw new Error('Expected iOS Info.plist was not generated.');

  let plist = await readFile(plistPath, 'utf8');
  const entries = [
    ['CFBundleDisplayName', 'عَمِّر'],
    ['NSCameraUsageDescription', 'يستخدم عَمِّر الكاميرا لتوثيق تقدم المشروع ورفع صور الموقع والعيوب والاستلام.'],
    ['NSPhotoLibraryUsageDescription', 'يتيح عَمِّر اختيار صور ومستندات المشروع من مكتبة الصور عند إرفاقها.'],
    ['NSPhotoLibraryAddUsageDescription', 'قد يحفظ عَمِّر الصور التي يختار المستخدم حفظها على جهازه.'],
    ['ITSAppUsesNonExemptEncryption', 'false']
  ];

  for (const [key, value] of entries) {
    const escaped = value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    const keyPattern = new RegExp('<key>' + key + '<\\/key>[\\s\\S]*?<\\/string>|<key>' + key + '<\\/key>[\\s\\S]*?<\\/true>|<key>' + key + '<\\/key>[\\s\\S]*?<\\/false>');
    const entry = '<key>' + key + '</key>' + (value === 'false' ? '<false/>' : '<string>' + escaped + '</string>');
    if (keyPattern.test(plist)) {
      plist = plist.replace(keyPattern, entry);
    } else {
      plist = plist.replace('</dict>', '    ' + entry + '\n</dict>');
    }
  }

  await writeFile(plistPath, plist, 'utf8');
}

console.log('AMMIR ' + platform + ' native project prepared.');