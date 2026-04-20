# pylint: disable=too-many-locals
"""
Smoke test to catch obvious ABI-mismatch related issues with torch <-> torchcodec
    and torch <-> torchaudio
"""
import sys
import os
from tempfile import TemporaryDirectory
import torch
import torchaudio
import torchcodec
from torch.testing import assert_close
from torchaudio import transforms as audio_transf
from torchcodec.encoders import AudioEncoder
from torchcodec.decoders import AudioDecoder


def _print_env_info() -> None:

    python_ver_str = sys.version.replace("\n", " ")
    print("============ CPU ABI SANITY ONLY ============")
    print("=== Relevant Environment Info of Versions ===")
    print(f"Python: {python_ver_str}")
    print(f"torch: {torch.__version__}")
    print(f"torchaudio: {torchaudio.__version__}")
    print(f"torchcodec: {torchcodec.__version__}")


def _make_rand_wav_files(tmpdir: str,
                         num_files: int = 5,
                         sample_rate: int = 16000) -> list[str]:
    """
    Generate `num_files` WAV files in `tmpdir` directory at
        sample rate `sample_rate` each, where each WAV file
        contains a pure tone mixed with gaussian noise and
        then clamped to between -1.0 and 1.0 in amplitude

    Returns: list of corresponding WAV file paths
    """

    duration_sec = 1.0
    init_freq_hz = 440.0
    semitone_multip_interv = 2.0 ** (1.0 / 12.0)
    pure_amplitude = 0.5
    target_snr_db = 3.0

    torch.manual_seed(39285)
    sample_time_pts = \
        torch.arange(int(sample_rate * duration_sec),
                                   dtype=torch.float32) / float(sample_rate)
    paths_list = []

    for idx in range(num_files):

        tone_pcm = pure_amplitude * \
                       torch.sin(2.0 * torch.pi * init_freq_hz * \
                                    (semitone_multip_interv ** idx) * \
                                                           sample_time_pts)
        noise_pcm = torch.randn_like(sample_time_pts)
        tone_power = tone_pcm.square().mean()
        noise_power = noise_pcm.square().mean()
        snr_scale = torch.sqrt(tone_power / (noise_power * (10.0 ** (target_snr_db / 10.0))))
        mixed_pcm = (tone_pcm + snr_scale * noise_pcm).clamp(-1.0, 1.0).unsqueeze(0)
        encoder_with_pcm = AudioEncoder(samples=mixed_pcm, sample_rate=sample_rate)
        wav_path_str = os.path.join(tmpdir, f"smoke_test_file_{idx}.wav")
        encoder_with_pcm.to_file(wav_path_str)
        paths_list.append(wav_path_str)

    return paths_list


def _decode_wave_file_n_print_info(filepath: str) -> None:
    """
    Given a path to a WAV file, decodes that wave file and
       prints some basic info about the waveform stored in that
       WAV file.
    """

    gain_adj_ratio = 0.6
    relative_tol = 1e-5
    absolute_tol = 1e-4
    decoder_from_file = AudioDecoder(filepath)
    audio_samples_data = decoder_from_file.get_all_samples()
    print(f"=== Info about waveform in file '{filepath}' ===")
    stdev_amp, mean_amp = torch.std_mean(audio_samples_data.data)
    stdev_amp_item = stdev_amp.item()
    mean_amp_item = mean_amp.item()
    print(f"Before {gain_adj_ratio:.3f} gain adjust -- mean: " + \
            f"{mean_amp_item:12.5e}, stdev: {stdev_amp_item:12.5e}")

    quiet_transf = audio_transf.Vol(gain=gain_adj_ratio,
                                    gain_type="amplitude")
    quieted_audio_data = quiet_transf(audio_samples_data.data)
    stdev_amp_after, mean_amp_after = torch.std_mean(quieted_audio_data)
    stdev_amp_item = stdev_amp_after.item()
    mean_amp_item = mean_amp_after.item()
    print(f"After {gain_adj_ratio:.3f} gain adjust --- mean: " + \
            f"{mean_amp_item:12.5e}, stdev: {stdev_amp_item:12.5e}")
    print("Checking that stdev and mean " + \
            "transformed as approximately expected...")
    assert_close(mean_amp_after, 0.6 * mean_amp,
                 rtol=relative_tol, atol=absolute_tol)
    assert_close(stdev_amp_after, 0.6 * stdev_amp,
                 rtol=relative_tol, atol=absolute_tol)
    print("Testing with 'assert_close' passed! " + \
            f"(rtol {relative_tol:.3e}, atol {absolute_tol:.3e})")

if __name__ == "__main__":

    _print_env_info()

    with TemporaryDirectory(prefix="audio_abi_smoke_") as tmpdir_inst:
        list_of_wavs = _make_rand_wav_files(tmpdir_inst)
        for wav_file_path in list_of_wavs:
            _decode_wave_file_n_print_info(wav_file_path)
    print("======= CPU TORCH/AUDIO/CODEC ABI CPU SANITY PASSED =======")
