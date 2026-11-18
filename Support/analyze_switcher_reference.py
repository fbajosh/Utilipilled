#!/usr/bin/env python3
"""Measure the supplied eight-app Retina switcher reference; leave input files untouched.

Requires numpy, scipy and Pillow. All coordinates are screenshot pixels. This is
an interior backdrop approximation, not an implementation of Apple's glass shader.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from scipy.optimize import minimize_scalar


def fit_backdrop(before, after, mask, validation_mask, space):
    def linear(x):
        return np.where(x <= .04045, x / 12.92, ((x + .055) / 1.055) ** 2.4)
    source = before if space == 'encoded' else linear(before)
    target = after if space == 'encoded' else linear(after)
    def evaluate(sigma, detail=False):
        blurred = gaussian_filter(source, (sigma, sigma, 0)) if sigma > 0 else source
        design = np.column_stack((blurred[mask], np.ones(mask.sum())))
        coefficients = np.linalg.lstsq(design, target[mask], rcond=None)[0]
        residual = design @ coefficients - target[mask]
        mse = float(np.mean(residual ** 2))
        if not detail:
            return mse
        validation = np.column_stack((blurred[validation_mask], np.ones(validation_mask.sum())))
        return {'sigma_pixels': float(sigma), 'sigma_points': float(sigma / 2),
                'training_rmse_0_to_1': mse ** .5,
                'validation_rmse_0_to_1': float(np.mean((validation @ coefficients - target[validation_mask]) ** 2)) ** .5,
                'affine_rgb_coefficients': coefficients.tolist()}
    result = minimize_scalar(evaluate, bounds=(.1, 18), method='bounded', options={'xatol': .01})
    return evaluate(result.x, detail=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--background', type=Path, required=True)
    parser.add_argument('--native', type=Path, required=True)
    parser.add_argument('--without', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    native = Image.open(args.native).convert('RGB')
    without = Image.open(args.without).convert('RGB')
    if native.size != without.size or native.size != (2880, 1864):
        raise ValueError('This measured fixture expects aligned 2880 × 1864 screenshots')
    a, b = np.asarray(native, dtype=float)/255, np.asarray(without, dtype=float)/255
    alignment = []
    for box in [(100,410,2700,650), (100,1200,2700,1500)]:
        x0,y0,x1,y1 = box
        difference = abs(a[y0:y1,x0:x1]-b[y0:y1,x0:x1])
        alignment.append({'rectangle_pixels': box, 'mean_absolute_error_255': float(difference.mean()*255),
                          'exact_pixel_fraction': float(np.mean(difference.max(axis=2)==0))})
    # Narrow strips halfway between unselected icons, well away from the outer rim
    # and the Chrome selection effect. Hold out two complete spatial strips.
    x0,y0,x1,y1 = 300,730,2580,1130
    y,x = np.mgrid[y0:y1,x0:x1]
    train, validation = np.zeros(x.shape, bool), np.zeros(x.shape, bool)
    for index, center in enumerate([1174,1442,1710,1978,2246]):
        strip = (abs(x-center)<7) & (y>=850) & (y<1010)
        if index in [1,4]: validation |= strip
        else: train |= strip
    fits = {space: fit_backdrop(b[y0:y1,x0:x1],a[y0:y1,x0:x1],train,validation,space)
            for space in ['encoded', 'linear']}
    report = {
        'inputs': {key: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'size_pixels': Image.open(path).size} for key, path in [('background', args.background), ('native', args.native), ('without', args.without)]},
        'capture_scale': 2,
        'source_sha256': {key: hashlib.sha256(path.read_bytes()).hexdigest() for key,path in
                          [('background',args.background),('native',args.native),('without',args.without)]},
        'screenshot_pixels': native.size, 'screenshot_scale': 2,
        'alignment_checks': alignment,
        'measured_layout_points': {'applications':8,'icon_center_pitch':134,'outer_horizontal_padding':20,
            'panel_width':1112,'panel_height':176,'source_icon_size':128,'selection_size':120,
            'selection_corner_radius_candidate':32,'panel_corner_radius_candidate':56,
            'font_candidate':'system 13 bold'},
        'backdrop_fits': fits,
        'limits': ['Layout coordinates have edge/shadow uncertainty and require replacement comparison.',
                   'A Gaussian plus affine color fit approximates flat interior only; edge refraction is excluded.',
                   'A single periodic test pattern cannot uniquely identify the native blur kernel.',
                   'No full-screen placement information is inferred from the earlier cropped reference.'],
    }
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    # Diagnostic crops retain original pixels; they are not edited replacement assets.
    native.crop((300,730,2580,1130)).save(args.output.parent/'native-panel.png')
    without.crop((300,730,2580,1130)).save(args.output.parent/'without-panel.png')
    print(json.dumps({'alignment':alignment,'interior_fits':fits},indent=2))


if __name__ == '__main__': main()
