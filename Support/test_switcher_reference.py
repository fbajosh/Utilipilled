import unittest
import numpy as np
from scipy.ndimage import gaussian_filter
from analyze_switcher_reference import fit_backdrop


class ReferenceFitChecks(unittest.TestCase):
    def test_known_blur_and_color_transform_are_recovered(self):
        source = np.random.default_rng(481).uniform(0, 1, (64, 96, 3))
        expected_sigma = 2.5
        blurred = gaussian_filter(source, (expected_sigma, expected_sigma, 0))
        target = blurred @ np.array([[.8, .02, .01], [.01, .75, .02], [.02, .01, .85]]) + [.05, .06, .04]
        y, x = np.mgrid[:64, :96]
        inside = (y > 8) & (y < 56) & (x > 8) & (x < 88)
        training, validation = inside & (x < 48), inside & (x >= 48)
        result = fit_backdrop(source, target, training, validation, 'encoded')
        self.assertAlmostEqual(result['sigma_pixels'], expected_sigma, delta=.02)
        self.assertLess(result['validation_rmse_0_to_1'], 1e-4)


if __name__ == '__main__': unittest.main()
