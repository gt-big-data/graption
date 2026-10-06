#allows me to measure processing time per audio clip
import time
from pathlib import Path #finds all the audio files within test_audio

#imports Pytorch, ML framework for audEERING model
import torch
import torch.nn as nn #neural-network components
import soundfile as sf #loads in the audio files + allows for deterministric qualities

from scipy.signal import resample_poly #resamples audio from 48,000 Hz to 16,000 Hz
from transformers import Wav2Vec2Processor #prepares raw audio for NN
#underlying Wav2Vec2 model + functionality
from transformers.models.wav2vec2.modeling_wav2vec2 import (
    Wav2Vec2Model,
    Wav2Vec2PreTrainedModel,
)

#using the same pretrained audEERING model from Hugging Face
MODEL_NAME = "audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim"
#retrieve necessary test audio files from test_audio folder
AUDIO_FOLDER = "ml/tone/test_audio"

#NN head used by the audEERING model
#outputs three values: arousal, dominance, and valence
class RegressionHead(nn.Module):
    def __init__(self, config):
        super().__init__()
        #Linear Layer #1 transforms the Wav2Vec2 representation
        self.dense = nn.Linear(config.hidden_size, config.hidden_size)
        #dropout reduces unnecessary dependence on the individual features
        self.dropout = nn.Dropout(config.final_dropout)
        #Final Linear Layer produces the three emotion dimensions
        self.out_proj = nn.Linear(config.hidden_size, config.num_labels)

    def forward(self, features):
        #dropout for the input features
        x = self.dropout(features)
        #pass the features through Linear Layer #1
        x = self.dense(x)
        #tanh activation function (used because it matches the architecture from the pretrained audEEERING model which had trained the weights we are using)
        x = torch.tanh(x)
        #dropout applied again before the Final Linear Layer
        x = self.dropout(x)
        #Produce the model's three output values
        return self.out_proj(x)

#maintains the architecture expected by the pretrained audEERING checkpoint
class EmotionModel(Wav2Vec2PreTrainedModel):
    def __init__(self, config):
        super().__init__(config)
        #load in the Wav2Vec2 audio model
        self.wav2vec2 = Wav2Vec2Model(config)
        #attach the pretrained audEERING regression head (names must match)
        self.classifier = RegressionHead(config)
        #initialize the model structure before loading pretrained weights
        self.post_init()

    def forward(self, input_values):
        #Send the processed audio through Wav2Vec2
        outputs = self.wav2vec2(input_values)
        #Get the hidden representation produced by Wav2Vec2
        hidden_states = outputs[0]
        #average the hidden states across the time dimension
        hidden_states = torch.mean(hidden_states, dim=1)
        #use the regression head to produce emotion scores
        logits = self.classifier(hidden_states)
        return hidden_states, logits

#Load in the audio processor using locally available files <-- raw audio
processor = Wav2Vec2Processor.from_pretrained(
    MODEL_NAME,
    local_files_only =True, #prevents Transformers from connecting to Hugging Face which results in error
)

#Load in the pretrained audEERING model from the local cache
model = EmotionModel.from_pretrained(
    MODEL_NAME,
    local_files_only =True,
)

#Evaluate the model for prediction, not training
model.eval()

def load_audio(audio_file):
    #read in the audio file which contains sound samples and "sample_rate"
    #tells us how many samples occur in each second
    audio, sample_rate = sf.read(audio_file)

    #if there are multiple channels, average them to create 1 mono signal
    if audio.ndim > 1:
        audio = audio.mean(axis=1)

    #since model expects audio sample to be 16000, we need to resample our current audio files
    if sample_rate != 16000:
        audio = resample_poly(audio, 16000, sample_rate)
        sample_rate = 16000

    return audio, sample_rate

#the following thresholds are defined in the GRAPTION_CONTEXT.md
def map_tag(arousal, valence):

    #High arousal means that the voice has a lot energy
    #High valence means the emotion is more positive

    if arousal > 0.65 and valence > 0.55:
        return "excited"

    #High arousal + low valence = upset/negative high-energy tone
    if arousal > 0.65 and valence < 0.4:
        return "upset"

    #Low arousal indicates a calm or low-energy tone
    if arousal < 0.3:
        return "calm"

    #if no rules are met, there is no evidence to assign one of the three tags
    else:
        return "none"

#extract intended category from filename
def extract_tag(audio_file):
    #use first part of filename as the intended category
    #this is bc filenames are organized as calm_clip_one.mp3
    filename = Path(audio_file).name
    return filename.split("_")[0]  # Assuming the category is the first part of the filename separated by underscores

#function that runs the model on one clip and measures its infernece time
def analyze_clip(audio_file):

    #start a timer right before processing a specific individual clip
    start_time = time.perf_counter()

    #remember to convert it to required audio format required by audEERING model
    audio, sample_rate = load_audio(audio_file)

    #processor converts audio samples into tensors that the Wav2Vec2 model can comprehend
    inputs = processor(
        audio,
        sampling_rate=sample_rate,
        return_tensors="pt",
    )


    #disable gradient calcs since we only make predictions not training model
    with torch.no_grad():
        #processed audio is run through model
        _, outputs = model(inputs.input_values)

    #retrieve the three values in specified order
    arousal, dominance, valence = outputs[0].tolist()

    #convert the arousal and valence scores into one tone tag
    tag = map_tag(arousal, valence)

    #Stop the timer after processing the clip
    elapsed_time = time.perf_counter() - start_time

    return {
        "file": Path(audio_file).name,
        "arousal": arousal,
        "dominance": dominance,
        "valence": valence,
        "tag": tag,
        "elapsed_time": elapsed_time
    }

#retrieve all mp3 recordings from test_audio folder
audio_files = sorted(Path(AUDIO_FOLDER).glob("*.mp3"))

#Check: print out number of files retrieved to ensure all clips were recognized
print(f"Found {len(audio_files)} audio files. \n")

#Process each audio file one at a time
for audio_file in audio_files:
    #analyze the clip and store its results
    result = analyze_clip(audio_file)

    #get the intended category from the filename
    expected_tag = extract_tag(audio_file)

    #check if model's tag name matches intended filename category
    match = result['tag'] == expected_tag

    #print the filename so we can correlate results to the original file
    print(f"File: {result['file']}")

    #print the results for each clip
    print(f"Arousal: {result['arousal']:.4f}")
    print(f"Valence: {result['valence']:.4f}")
    print(f"Dominance: {result['dominance']:.4f}")

    #prints the assigned tag created by the threshold rules
    print(f"Tag: {result['tag']}")

    #print if the model's prediction matches the expected category
    print(f"Match: {match}")

    #print how long it took to process the clip
    print(f"Time: {result['elapsed_time']:.2f} seconds")

    print() #blank line before repeating code above for next audio clip

