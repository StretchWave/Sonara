import os
from PIL import Image

def generate_assets():
    logo_path = 'logo.png'
    if not os.path.exists(logo_path):
        raise FileNotFoundError(f"Logo not found at {logo_path}")

    base_img = Image.open(logo_path).convert('RGBA')
    print(f"Loaded source logo from {logo_path}: {base_img.size}, mode={base_img.mode}")

    # 1. Main Flutter Assets
    os.makedirs('assets/icons', exist_ok=True)
    icon_512 = base_img.resize((512, 512), Image.Resampling.LANCZOS)
    icon_512.save('assets/icons/icon.png', format='PNG')
    print("Updated assets/icons/icon.png (512x512)")

    # Windows ICO for assets and runner
    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    base_img.save('assets/icons/icon.ico', format='ICO', sizes=ico_sizes)
    print("Updated assets/icons/icon.ico")

    os.makedirs('windows/runner/resources', exist_ok=True)
    base_img.save('windows/runner/resources/app_icon.ico', format='ICO', sizes=ico_sizes)
    print("Updated windows/runner/resources/app_icon.ico")

    # 2. Fastlane metadata
    os.makedirs('fastlane/metadata/android/en-US/images', exist_ok=True)
    icon_512.save('fastlane/metadata/android/en-US/images/icon.png', format='PNG')
    print("Updated fastlane/metadata/android/en-US/images/icon.png")

    # 3. Web assets
    os.makedirs('web/icons', exist_ok=True)
    base_img.resize((32, 32), Image.Resampling.LANCZOS).save('web/favicon.png', format='PNG')
    base_img.resize((192, 192), Image.Resampling.LANCZOS).save('web/icons/Icon-192.png', format='PNG')
    icon_512.save('web/icons/Icon-512.png', format='PNG')
    base_img.resize((192, 192), Image.Resampling.LANCZOS).save('web/icons/Icon-maskable-192.png', format='PNG')
    icon_512.save('web/icons/Icon-maskable-512.png', format='PNG')
    print("Updated web favicon and icon set")

    # 4. macOS assets
    macos_dir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    if os.path.exists(macos_dir):
        sizes = {
            'app_icon_16.png': (16, 16),
            'app_icon_32.png': (32, 32),
            'app_icon_64.png': (64, 64),
            'app_icon_128.png': (128, 128),
            'app_icon_256.png': (256, 256),
            'app_icon_512.png': (512, 512),
            'app_icon_1024.png': (1024, 1024),
        }
        for filename, sz in sizes.items():
            out_p = os.path.join(macos_dir, filename)
            base_img.resize(sz, Image.Resampling.LANCZOS).save(out_p, format='PNG')
        print("Updated macOS AppIcon set")

    # 5. iOS assets
    ios_icon_dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    if os.path.exists(ios_icon_dir):
        ios_sizes = {
            'Icon-App-20x20@1x.png': (20, 20),
            'Icon-App-20x20@2x.png': (40, 40),
            'Icon-App-20x20@3x.png': (60, 60),
            'Icon-App-29x29@1x.png': (29, 29),
            'Icon-App-29x29@2x.png': (58, 58),
            'Icon-App-29x29@3x.png': (87, 87),
            'Icon-App-40x40@1x.png': (40, 40),
            'Icon-App-40x40@2x.png': (80, 80),
            'Icon-App-40x40@3x.png': (120, 120),
            'Icon-App-50x50@1x.png': (50, 50),
            'Icon-App-50x50@2x.png': (100, 100),
            'Icon-App-57x57@1x.png': (57, 57),
            'Icon-App-57x57@2x.png': (114, 114),
            'Icon-App-60x60@2x.png': (120, 120),
            'Icon-App-60x60@3x.png': (180, 180),
            'Icon-App-72x72@1x.png': (72, 72),
            'Icon-App-72x72@2x.png': (144, 144),
            'Icon-App-76x76@1x.png': (76, 76),
            'Icon-App-76x76@2x.png': (152, 152),
            'Icon-App-83.5x83.5@2x.png': (167, 167),
            'Icon-App-1024x1024@1x.png': (1024, 1024),
        }
        for filename, sz in ios_sizes.items():
            out_p = os.path.join(ios_icon_dir, filename)
            base_img.resize(sz, Image.Resampling.LANCZOS).save(out_p, format='PNG')
        print("Updated iOS AppIcon set")

    # 6. iOS Launch Image set
    ios_launch_dir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
    if os.path.exists(ios_launch_dir):
        base_img.resize((180, 180), Image.Resampling.LANCZOS).save(os.path.join(ios_launch_dir, 'LaunchImage.png'), format='PNG')
        base_img.resize((360, 360), Image.Resampling.LANCZOS).save(os.path.join(ios_launch_dir, 'LaunchImage@2x.png'), format='PNG')
        base_img.resize((540, 540), Image.Resampling.LANCZOS).save(os.path.join(ios_launch_dir, 'LaunchImage@3x.png'), format='PNG')
        print("Updated iOS LaunchImage set")

    # 7. Android App Icons & Adaptive Foregrounds
    android_res = 'android/app/src/main/res'
    mipmap_configs = {
        'mipmap-mdpi': (48, 108),
        'mipmap-hdpi': (72, 162),
        'mipmap-xhdpi': (96, 216),
        'mipmap-xxhdpi': (144, 324),
        'mipmap-xxxhdpi': (192, 432),
    }
    for folder, (launcher_sz, fg_sz) in mipmap_configs.items():
        folder_p = os.path.join(android_res, folder)
        os.makedirs(folder_p, exist_ok=True)
        # Legacy ic_launcher: square resized logo
        base_img.resize((launcher_sz, launcher_sz), Image.Resampling.LANCZOS).save(
            os.path.join(folder_p, 'ic_launcher.png'), format='PNG'
        )

        # Adaptive icon foreground: 108x108 grid with ~66-72dp icon centered
        fg_canvas = Image.new('RGBA', (fg_sz, fg_sz), (0, 0, 0, 0))
        icon_inner_sz = int(fg_sz * 0.66)
        scaled_icon = base_img.resize((icon_inner_sz, icon_inner_sz), Image.Resampling.LANCZOS)
        offset = ((fg_sz - icon_inner_sz) // 2, (fg_sz - icon_inner_sz) // 2)
        fg_canvas.paste(scaled_icon, offset, scaled_icon)
        fg_canvas.save(os.path.join(folder_p, 'ic_launcher_foreground.png'), format='PNG')

    print("Updated Android mipmap launcher and adaptive foreground icons")

    # 8. Android Splash / Launch Screen Logo
    # Create drawable density buckets for splash_logo
    splash_configs = {
        'drawable-mdpi': (160, 160),
        'drawable-hdpi': (240, 240),
        'drawable-xhdpi': (320, 320),
        'drawable-xxhdpi': (480, 480),
        'drawable-xxxhdpi': (640, 640),
        'drawable': (320, 320),
    }
    for folder, sz in splash_configs.items():
        f_dir = os.path.join(android_res, folder)
        os.makedirs(f_dir, exist_ok=True)
        base_img.resize(sz, Image.Resampling.LANCZOS).save(
            os.path.join(f_dir, 'splash_logo.png'), format='PNG'
        )
    print("Created Android splash_logo.png across drawable densities")

if __name__ == '__main__':
    generate_assets()
