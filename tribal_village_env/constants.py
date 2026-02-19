"""Constants for the Tribal Village environment.

This module re-exports default values from the typed config module for
backward compatibility. New code should use the config classes directly:

    from tribal_village_env.config import EnvironmentConfig, PPOConfig, TrainingConfig

Legacy usage (still supported):
    from tribal_village_env.constants import DEFAULT_MAX_STEPS, DEFAULT_LEARNING_RATE
"""

from tribal_village_env.config import (
    DEFAULT_ANSI_STEPS,
    DEFAULT_PROFILE_STEPS,
    OBS_MAX_VALUE,
    OBS_MIN_VALUE,
    OBS_NORMALIZATION_FACTOR,
    EnvironmentConfig,
    PPOConfig,
    PolicyConfig,
    TrainingConfig,
)

# Environment defaults (from EnvironmentConfig)
_env = EnvironmentConfig()
DEFAULT_MAX_STEPS = _env.max_steps
DEFAULT_RENDER_SCALE = _env.render_scale
DEFAULT_ANSI_BUFFER_SIZE = _env.ansi_buffer_size

# Training defaults (from TrainingConfig)
_train = TrainingConfig()
DEFAULT_TRAIN_MAX_STEPS = _train.max_steps
DEFAULT_NUM_ENVS = _train.num_envs
DEFAULT_CHECKPOINT_INTERVAL = _train.checkpoint_interval

# PPO hyperparameters (from PPOConfig)
_ppo = PPOConfig()
DEFAULT_LEARNING_RATE = _ppo.learning_rate
DEFAULT_BPTT_HORIZON = _ppo.bptt_horizon
DEFAULT_ADAM_EPS = _ppo.adam_eps
DEFAULT_GAMMA = _ppo.gamma
DEFAULT_GAE_LAMBDA = _ppo.gae_lambda
DEFAULT_UPDATE_EPOCHS = _ppo.update_epochs
DEFAULT_CLIP_COEF = _ppo.clip_coef
DEFAULT_VF_COEF = _ppo.vf_coef
DEFAULT_VF_CLIP_COEF = _ppo.vf_clip_coef
DEFAULT_MAX_GRAD_NORM = _ppo.max_grad_norm
DEFAULT_ENT_COEF = _ppo.ent_coef
DEFAULT_ADAM_BETA1 = _ppo.adam_beta1
DEFAULT_ADAM_BETA2 = _ppo.adam_beta2
DEFAULT_MAX_MINIBATCH_SIZE = _ppo.max_minibatch_size
DEFAULT_VTRACE_RHO_CLIP = _ppo.vtrace_rho_clip
DEFAULT_VTRACE_C_CLIP = _ppo.vtrace_c_clip
DEFAULT_PRIO_ALPHA = _ppo.prio_alpha
DEFAULT_PRIO_BETA0 = _ppo.prio_beta0

# Policy defaults (from PolicyConfig)
_policy = PolicyConfig()
DEFAULT_HIDDEN_SIZE = _policy.hidden_size

# Re-export config classes for convenience
__all__ = [
    # Observation space bounds
    "OBS_MIN_VALUE",
    "OBS_MAX_VALUE",
    "OBS_NORMALIZATION_FACTOR",
    # Environment defaults
    "DEFAULT_MAX_STEPS",
    "DEFAULT_RENDER_SCALE",
    "DEFAULT_ANSI_BUFFER_SIZE",
    # CLI defaults
    "DEFAULT_ANSI_STEPS",
    "DEFAULT_PROFILE_STEPS",
    # Training defaults
    "DEFAULT_TRAIN_MAX_STEPS",
    "DEFAULT_NUM_ENVS",
    "DEFAULT_CHECKPOINT_INTERVAL",
    # PPO hyperparameters
    "DEFAULT_LEARNING_RATE",
    "DEFAULT_BPTT_HORIZON",
    "DEFAULT_ADAM_EPS",
    "DEFAULT_GAMMA",
    "DEFAULT_GAE_LAMBDA",
    "DEFAULT_UPDATE_EPOCHS",
    "DEFAULT_CLIP_COEF",
    "DEFAULT_VF_COEF",
    "DEFAULT_VF_CLIP_COEF",
    "DEFAULT_MAX_GRAD_NORM",
    "DEFAULT_ENT_COEF",
    "DEFAULT_ADAM_BETA1",
    "DEFAULT_ADAM_BETA2",
    "DEFAULT_MAX_MINIBATCH_SIZE",
    "DEFAULT_VTRACE_RHO_CLIP",
    "DEFAULT_VTRACE_C_CLIP",
    "DEFAULT_PRIO_ALPHA",
    "DEFAULT_PRIO_BETA0",
    # Policy defaults
    "DEFAULT_HIDDEN_SIZE",
    # Config classes
    "EnvironmentConfig",
    "PPOConfig",
    "PolicyConfig",
    "TrainingConfig",
]
