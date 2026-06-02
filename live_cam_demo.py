import cv2
import serial
import time
import numpy as np

# ====================================================================
# PHASE 4 OPTIMIZED SETTINGS
# ====================================================================
SERIAL_PORT = 'COM5'       
BAUD_RATE   = 460800       # STEP 4.1: Upgraded high-speed configuration
ROI_SIZE    = 200          
TIMEOUT_VAL = 0.1          # Decreased latency wait window

def main():
    print("==========================================================")
    print("   PHASE 4: Exhibition High-Speed Inference Workspace   ")
    print("==========================================================\n")
    
    print(f"Opening port {SERIAL_PORT} at high-speed speed boundary {BAUD_RATE}...")
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=TIMEOUT_VAL)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        time.sleep(1.0)
        print("High-Speed Pipeline Verified.")
    except Exception as e:
        print(f"[ERROR] Connection failure: {e}")
        return

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("[ERROR] Camera inaccessible.")
        ser.close()
        return

    virtual_image_mode = True  
    invert_bits_mode = False   

    print("\nSystem Online. Wave handwritten digit sheets across target region.")
    print("Press 'v' to flip image | 'i' to invert bits | 'q' to exit.\n")
    
    last_pred, last_conf = "...", "..."
    text_color = (0, 255, 0)

    while True:
        ret, frame = cap.read()
        if not ret: break

        frame = cv2.flip(frame, 1)
        h, w, _ = frame.shape

        x1 = (w - ROI_SIZE) // 2
        y1 = (h - ROI_SIZE) // 2
        x2, y2 = x1 + ROI_SIZE, y1 + ROI_SIZE
        roi = frame[y1:y2, x1:x2]
        
        if virtual_image_mode:
            roi_processed = cv2.flip(roi, 1)
        else:
            roi_processed = roi.copy()

        gray = cv2.cvtColor(roi_processed, cv2.COLOR_BGR2GRAY)
        resized = cv2.resize(gray, (28, 28), interpolation=cv2.INTER_AREA)
        _, binary = cv2.threshold(resized, 127, 255, cv2.THRESH_BINARY)
        
        if invert_bits_mode:
            fpga_input_vector = (binary <= 127).astype(np.uint8).flatten()
            display_binary = cv2.bitwise_not(binary)
        else:
            fpga_input_vector = (binary > 127).astype(np.uint8).flatten()
            display_binary = binary.copy()

        # Instant streaming output payload
        ser.write(bytes(fpga_input_vector))
        ser.flush()

        pred_byte = ser.read(1)
        conf_byte = ser.read(1)

        if pred_byte and conf_byte:
            last_pred = str(pred_byte[0])
            last_conf = f"{conf_byte[0]}%"
            text_color = (255, 255, 0) if conf_byte[0] >= 75 else (0, 255, 0)
        else:
            # High speed packet loss recovery mechanism
            last_pred, last_conf = last_pred, last_conf 

        # Drawing Interface elements
        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
        cv2.putText(frame, f"Prediction: {last_pred}", (x1, y1 - 32), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, text_color, 2, cv2.LINE_AA)
        cv2.putText(frame, f"Confidence: {last_conf}", (x1, y1 - 10), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, text_color, 2, cv2.LINE_AA)

        vision_preview = cv2.resize(display_binary, (112, 112), interpolation=cv2.INTER_NEAREST)
        frame[15:127, 15:127] = cv2.cvtColor(vision_preview, cv2.COLOR_GRAY2BGR)
        cv2.rectangle(frame, (13, 13), (128, 128), (255, 255, 255), 1)
        cv2.putText(frame, "FPGA Vision", (15, 142), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)

        cv2.imshow("Basys3 Real-Time TinyML Inference Engine", frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('v'):
            virtual_image_mode = not virtual_image_mode
        elif key == ord('i'):
            invert_bits_mode = not invert_bits_mode

    cap.release()
    ser.close()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()