"""Converts the fine-tuned PupilSegmentationModel to the
`PupilSegmentation.mlpackage` that Sober/Services/PupilCaptureService.swift
expects to find (Xcode compiles a bundled .mlpackage/.mlmodel to
.mlmodelc automatically at build time — nothing else needs to change on
the Swift side).

Input: a single-channel (grayscale) image, any size — Vision's
`imageCropAndScaleOption = .scaleFill` resizes the eye crop to whatever
input size this model declares (400x640, matching training) before
inference, and Core ML/Vision handle the RGB -> grayscale conversion
from the CIImage Sober hands it. All of the model's own preprocessing
(gamma, local-contrast-normalize, the final mean/std normalize, and the
4-class-to-3-class softmax merge) is part of the traced graph — Vision
only needs to hand it a resized image, nothing else.

Output: a (1, 3, 400, 640) probability map — channel order
(background, iris, pupil) — as a plain MLMultiArray feature, matching
`classifyPixels`'s `shape[0] == 3` branch in PupilCaptureService.swift.
"""

import argparse

import coremltools as ct
import torch

from model import PupilSegmentationModel


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", default="finetuned_pupil_segmentation.pt")
    parser.add_argument("--out", default="PupilSegmentation.mlpackage")
    args = parser.parse_args()

    model = PupilSegmentationModel()
    model.load_state_dict(torch.load(args.weights, map_location="cpu", weights_only=True))
    model.eval()

    example_input = torch.rand(1, 1, 400, 640)
    traced = torch.jit.trace(model, example_input)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="eye_image",
                shape=example_input.shape,
                color_layout=ct.colorlayout.GRAYSCALE,
                scale=1 / 255.0,
                bias=0.0,
            )
        ],
        outputs=[ct.TensorType(name="class_scores")],
        minimum_deployment_target=ct.target.iOS16,
        compute_units=ct.ComputeUnit.ALL,
        convert_to="mlprogram",
    )

    mlmodel.author = "Sober prototype — fine-tuned from RITnet (Chaudhary et al., ICCVW 2019), MIT License"
    mlmodel.short_description = (
        "3-class (background, iris, pupil) eye segmentation for the pupillary light "
        "reflex protocol. Backbone pretrained on OpenEDS2019, fine-tuned on OpenEDS2020 "
        "(both NIR VR-headset eye-tracker imagery) through a Core ML-compatible "
        "preprocessing substitute for RITnet's original CLAHE. Has NOT been fine-tuned "
        "on visible-light iPhone camera imagery — see Training/PupilSegmentation/README.md "
        "for the known domain-gap caveat before treating its accuracy on-device as validated."
    )
    mlmodel.save(args.out)
    print(f"saved {args.out}")


if __name__ == "__main__":
    main()
