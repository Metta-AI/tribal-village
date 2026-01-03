import vertexai
from vertexai.preview.generative_models import ImageGenerationModel
import argparse

def generate_image(project_id: str, location: str, prompt: str, output_file: str):
    """Generates an image using a prompt."""
    vertexai.init(project=project_id, location=location)

    model = ImageGenerationModel.from_pretrained("imagegeneration@006")

    images = model.generate_images(
        prompt=prompt,
        number_of_images=1,
    )

    if images:
        images[0].save(location=output_file, include_generation_parameters=True)
        print(f"Image generated and saved to {output_file}")
    else:
        print("Could not generate image.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-id", type=str, required=True, help="Your GCP project ID.")
    parser.add_argument("--location", type=str, default="us-central1", help="The GCP location to use.")
    parser.add_argument("--prompt", type=str, default="a majestic tribal village at sunset", help="The prompt for image generation.")
    parser.add_argument("--output-file", type=str, default="generated_image.png", help="The output file name.")
    args = parser.parse_args()

    generate_image(args.project_id, args.location, args.prompt, args.output_file)
