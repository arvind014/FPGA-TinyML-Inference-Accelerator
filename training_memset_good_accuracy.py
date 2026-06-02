import torch
import torch.nn as nn
import torch.optim as optim
import torchvision
import torchvision.transforms as transforms
import numpy as np

class RobustFPGACalculator(nn.Module):
    def __init__(self):
        super().__init__()
        self.layer = nn.Linear(784, 10, bias=True)

    def forward(self, x):
        return self.layer(x)

def add_noise(img, noise_prob=0.25):
    noisy = img.clone()
    random_tensor = torch.rand(noisy.shape)
    flip_mask = random_tensor < noise_prob
    noisy[flip_mask] = -noisy[flip_mask] # Flips pixels completely from +1 to -1 and vice versa
    return noisy

def main():
    print("Loading and preparing strict Binarized MNIST (+1.0 / -1.0)...")
    # Matches the FPGA hardware sign representation exactly
    transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Lambda(lambda x: torch.where(x > 0.5, 1.0, -1.0)),
        transforms.Lambda(lambda x: x.view(-1))
    ])

    trainset = torchvision.datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    trainloader = torch.utils.data.DataLoader(trainset, batch_size=64, shuffle=True)

    model = RobustFPGACalculator()
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.002) # Balanced learning rate

    print("Training Robust Model with Noise Augmentation (5 Epochs)...")
    for epoch in range(5):
        running_loss = 0.0
        for images, labels in trainloader:
            # Inject noise so the weights focus on core shapes, not fragile pixel links
            noisy_images = add_noise(images, noise_prob=0.20)

            optimizer.zero_grad()
            outputs = model(noisy_images)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()
        print(f"Epoch {epoch+1} Complete - Avg Loss: {running_loss/len(trainloader):.4f}")

    # Quantization 
    w = model.layer.weight.data
    b = model.layer.bias.data
    max_val = max(torch.max(torch.abs(w)).item(), torch.max(torch.abs(b)).item())
    scale = 127.0 / max_val
    w_q = torch.round(w * scale).int().numpy()
    b_q = torch.round(b * scale).int().numpy()

    print("\n── Exporting GOOD/ROBUST 4-Way Banked Weights ──")
    for b_idx in range(4):
        weight_file = f"weights_layer1_b{b_idx}.mem"
        with open(weight_file, 'w') as f:
            for neuron in range(10):
                for pixel_idx in range(b_idx, 784, 4):
                    value = w_q[neuron, pixel_idx]
                    f.write(f"{int(value) & 0xFF:02x}\n")
                    
    with open("biases.mem", 'w') as f:
        for value in b_q.flatten():
            f.write(f"{int(value) & 0xFF:02x}\n")
    print("Export complete. These weights are ready for high accuracy deployment.")

if __name__ == '__main__':
    main()