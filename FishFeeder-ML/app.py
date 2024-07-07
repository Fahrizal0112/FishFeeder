from flask import Flask, request, jsonify
import os
from werkzeug.utils import secure_filename
import tensorflow as tf
from tensorflow.keras.preprocessing import image
import numpy as np
from PIL import Image

app = Flask(__name__)

# Load model
model = tf.keras.models.load_model('model.h5')

# Load labels
with open('Label.txt', 'r') as file:
    labels = file.read().splitlines()

ALLOWED_EXTENSIONS = {'jpg', 'jpeg', 'png'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def preprocess_image(img_path):
    img = Image.open(img_path)
    img = img.resize((150, 150))
    img_array = np.array(img)
    img_array = np.expand_dims(img_array, axis=0)
    img_array = tf.keras.applications.mobilenet_v2.preprocess_input(img_array)
    return img_array

@app.route('/predict', methods=['POST'])
def predict():
    try:
        if 'image' not in request.files:
            return jsonify({'error': 'No image part in the request'}), 400

        file = request.files['image']

        if file.filename == '':
            return jsonify({'error': 'No selected image file'}), 400

        if file and allowed_file(file.filename):
            # Secure filename
            filename = secure_filename(file.filename)
            filepath = os.path.join('/tmp', filename)

            # Save the file locally
            file.save(filepath)

            # Preprocess the image
            img = preprocess_image(filepath)

            # Delete the local file after processing
            os.remove(filepath)

            # Make predictions
            predictions = model.predict(img)
            predicted_label = labels[np.argmax(predictions)]
            confidence = float(np.max(predictions))

            result = {'prediction': predicted_label, 'confidence': confidence}
            return jsonify(result)
        else:
            return jsonify({'error': 'Invalid file format. Supported formats: jpg, jpeg, png'}), 400

    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True, host="127.0.0.1", port=8000)
