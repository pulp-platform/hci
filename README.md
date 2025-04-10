[![Documentation Status](https://readthedocs.org/projects/hwpe-doc/badge/?version=latest)](https://hwpe-doc.readthedocs.io/en/latest/?badge=latest)
See documentation on https://hwpe-doc.readthedocs.io/en/latest/.

# Repository content
The `hci` repository contains the definition of the Heterogeneous Cluster Interconnect (HCI) interfaces used with HWPEs (HW Processing Engines), as well as the IPs necessary to manage the streams and construct streamers, used in all recent (2019-ongoing) PULP platform HWPEs, e.g.:
 - https://github.com/pulp-platform/rbe
 - https://github.com/pulp-platform/ne16
 - https://github.com/pulp-platform/neureka
 - https://github.com/pulp-platform/redmule

# Style guide
These IPs use a slightly different style than other PULP IPs. Refer to `STYLE.md` for some indications.

# References
If you are using HCI IPs for an academic publication, we recommend citing one or more of the following papers, which describe several aspects of the HCI system:
```
@article{garofalo2022darkside,
  author={Garofalo, Angelo and Tortorella, Yvan and Perotti, Matteo and Valente, Luca and Nadalini, Alessandro and Benini, Luca and Rossi, Davide and Conti, Francesco},
  journal={IEEE Open Journal of the Solid-State Circuits Society}, 
  title={DARKSIDE: A Heterogeneous RISC-V Compute Cluster for Extreme-Edge On-Chip DNN Inference and Training}, 
  year={2022},
  volume={2},
  number={},
  pages={231-243},
  keywords={Clustering methods;Low power electronics;Engines;System-on-chip;Human computer interaction;Hardware;Tensors;Heterogeneous cluster;tensor product engine (TPE);ultralow-power AI},
  doi={10.1109/OJSSCS.2022.3210082}
}
@article{conti2023marsellus,
  author={Conti, Francesco and Paulin, Gianna and Garofalo, Angelo and Rossi, Davide and Di Mauro, Alfio and Rutishauser, Georg and Ottavi, Gianmarco and Eggiman, Manuel and Okuhara, Hayate and Benini, Luca},
  journal={IEEE Journal of Solid-State Circuits}, 
  title={Marsellus: A Heterogeneous RISC-V AI-IoT End-Node SoC With 2–8 b DNN Acceleration and 30%-Boost Adaptive Body Biasing}, 
  year={2024},
  volume={59},
  number={1},
  pages={128-142},
  keywords={Artificial neural networks;Computer architecture;Task analysis;Engines;System-on-chip;Kernel;Microcontrollers;Artificial intelligence (AI);deep neural networks (DNNs);digital signal processor (DSP);heterogeneous architecture;Internet of Things (IoT);RISC-V;system-on-chip (SoC)},
  doi={10.1109/JSSC.2023.3318301}
}
@inproceedings{prasad2023archimedes,
  author={Prasad, Arpan Suravi and Benini, Luca and Conti, Francesco},
  booktitle={2023 60th ACM/IEEE Design Automation Conference (DAC)}, 
  title={Specialization meets Flexibility: a Heterogeneous Architecture for High-Efficiency, High-flexibility AR/VR Processing}, 
  year={2023},
  volume={},
  number={},
  pages={1-6},
  keywords={Power demand;Design automation;Wearable computers;Pipelines;Gaze tracking;Energy efficiency;Task analysis},
  doi={10.1109/DAC56929.2023.10247945}
}
```
# HCI Verification Environment

This repository also contains an environment for verifying the Heterogeneous Cluster Interconnect (HCI)

## Setup Instructions

Before running the simulation, follow these steps:

1. **Configure HCI Parameters** <br>
Edit the 'hci_config' file inside the config folder and insert the correct configuration values as needed for your verification environment. <br>  

2. **Run Setup**
```bash
make setup
```  
3. **Configure the Parameters of the Masters** <br>
Edit the files in the folder /config/hardware_config/masters_config to set the parameters of the masters  

4. **Choose the Test** <br>
Choose the test in /config/config.mk  

5. **Create stimuli** <br>
```bash
make stimuli
```  

6. **Run the simulation** <br>
```bash
make clean build run &
```