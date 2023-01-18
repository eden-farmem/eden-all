import os
import pandas as pd
import matplotlib.pyplot as plt

def get_files():
    data_dir="./data"
    files = [f for f in os.listdir(data_dir) if os.path.isfile(os.path.join(data_dir, f))]
    return files

def organize_files():
    files = get_files()
    file_dict=dict()
    for file in files:
        file_split = file.split("_")
        name, percent = file_split[1], file_split[2]
        percent=percent.split(".")[0]
        print(name,percent)
        if name not in file_dict:
            file_dict[name]=dict()
        file_dict[name][percent]=file
    return file_dict

file_dict=organize_files()
fig, ax = plt.subplots(1,1,figsize=(6, 6))

for name in file_dict:
    full = file_dict[name]["100"]
    nf = file_dict[name]["95"]
    print(full,nf)

    full_df = pd.read_csv("./data/"+full)
    nf_df = pd.read_csv("./data/"+nf)

    full_loc = full_df["loc"].values
    nf_loc = nf_df["loc"].values
    x_axis = nf_df["lmemp"].values
    ratio = [float(x)/float(y) for x,y in zip(full_loc,nf_loc)]
    print(full_loc)
    print(nf_loc)
    print(x_axis)
    print(ratio)

    ax.plot(x_axis,ratio, label=name)

ax.set_ylabel("Ratio of all faults to 95th percentile faults")
ax.set_xlabel("Local Memory Percentage")
ax.legend()
plt.tight_layout()
plt.savefig("exp1.pdf")


