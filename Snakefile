import os
import glob

configfile: "config_template.yaml"

# Results locations
REF_DIR = config["REF_DIR"]
SAMPLE_DIR = config["SAMPLE_DIR"]
SC_DIR = config["SC_DIR"]
BULK_DIR = config["BULK_DIR"]
CALLS_DIR = config["CALLS_DIR"]
LOGS_DIR = config["LOGS_DIR"]
REF = "data/scref/ref_source.fa"

# Simulation parameters
REFGENOME = config["REFGENOME"]
NSC = config["NSC"]
NPROTO = config["NPROTO"]
NSNV = config["NSNV"]
NBulk = config["NBulk"]
SEED = config["SEED"]
MEAN_COV = config["MEAN_COV"]
PBE1 = config["PBE1"]
PBE2 = config["PBE2"]
ADO_p = config["ADO_p"]
FP_p = config["FP_p"]


wildcard_constraints:
    single_cell = expand("after_wga_exp1_sc{samplenum}", samplenum = range(1, NSC + 1)),
    prototype = expand("before_wga_exp1_sc{samplenum}", samplenum = range(1, NPROTO + 1)),
    read = ["read1", "read2"],
    allele = ["a1", "a2"],
    n_b = range(1, NBulk + 1)

PROTOTYPES = expand("before_wga_exp1_sc{samplenum}", samplenum = range(1, NPROTO + 1))
ALLELES = ["a1", "a2"]
SINGLE_CELLS = expand("after_wga_exp1_sc{samplenum}", samplenum = range(1, NSC + 1))
READS = ["read1", "read2"]
N_B = range(1, NBulk + 1)


rule all:
    input:
        FLAGS = os.path.join(REF_DIR, "all_flags.csv"),
        BED = expand(os.path.join(REF_DIR, "snv_sc{n}.bed"), n = range(1,NSC+1)),
        A_BCFTOOLS = expand(os.path.join(CALLS_DIR, "bcftools/{single_cell}.vcf"), single_cell = SINGLE_CELLS),
        B_BCFTOOLS = expand(os.path.join(CALLS_DIR, "bcftools/bulk{n_b}.vcf"), n_b = N_B),
        A_MONOVAR = os.path.join(CALLS_DIR, "monovar/all_after.vcf"),
        B_MONOVAR = os.path.join(CALLS_DIR, "monovar/all_bulk.vcf")
    run:
        print("Simulation completed! {} bulk cells and {} single cells ".format(NBulk, NSC) + 
              "were simulated and can be found in {} and {} respectively.".format(BULK_DIR, SC_DIR))


rule clean:
    shell:
        "rm -rf {SC_DIR}/* {REF_DIR}/* {SAMPLE_DIR}/* {BULK_DIR}/* {CALLS_DIR}/* {LOGS_DIR}/*"


rule gen_scref:
    """Generate single-cell reference genome fasta files."""
    input:
        REFGENOME
    output:
        A_FASTA = expand(os.path.join(REF_DIR, "{single_cell}_{allele}.fa"), single_cell = SINGLE_CELLS, allele = ALLELES),
        BED = expand(os.path.join(REF_DIR, "snv_sc{n}.bed"), n = range(1, NSC + 1)),
        _REF = os.path.join(REF_DIR, "ref_source.fa"),
        B_FASTA = expand(os.path.join(REF_DIR, "{prototype}_{allele}.fa"), prototype = PROTOTYPES, allele = ALLELES),
        SNV_FLAGS = os.path.join(REF_DIR, "exp1_snv_flags.md")
    shell:
        "python src/gen-scref.py -f {input} -e 1 -n {NSC} -s {NSNV} -o wga -d {REF_DIR} -sd {SEED} -fp {FP_p} -ado {ADO_p}"


#rule gen_excess_scref:
#    input:
#        REFGENOME
#    output:
#        A_FASTA = expand(os.path.join(REF_DIR, "after_wga_exp1_sc{samplenum}_{allele}.fa"), samplenum = range(NPROTO + 1, NSC + 1), allele = ALLELES),
#        BED = expand(os.path.join(REF_DIR, "snv_sc{n}.bed"), n = range(NPROTO + 1, NSC + 1)),
#        #SNV_FLAGS = os.path.join(REF_DIR, "exp1_snv_flags_excess.md")
#    run:
#        from src import gen-scref as gen
#        import pandas as pd
#        import numpy as np
#
#        for e in range(NPROTO + 1, NSC + 1):
#            source = gen.filter_source(source = REFGENOME, target_size = 10**6)
#
#            N = len(source)
#            offset = int(0.1 * N)
#            snv_loc = np.linspace(start = offset, stop = N - offset, num = NSNV).astype(int)
#
#            T_snv = gen.gen_snv_transition_matrix()
#            alt_gtype = {loc: gen.sim_alt_gtype(ref = 2*source[loc], T_snv = T_snv)
#                         for loc in snv_loc}
#
#            (snv_mtx, p_lst) = gen.sim_snv_flags_mtx(NSNV, NPROTO - NSC)
#            sc_gtypes = gen.simulate_snv(source, snv_loc[snv_mtx[:,c]], alt_gtype)
#
#            outname = out+'_sc%d'%(c+1)
#
#            gen.write_sc(sc_obj = sc_gtypes, seq_type = 'wga_gtype', out = 'after_'+outname)
#
#            bed_df = pd.DataFrame({'chrom': "ref_source",
#                                   'chromStart': snv_loc[snv_mtx[:,c]],
#                                   'chromEnd': snv_loc[snv_mtx[:,c]]+1})
#            bed_df.to_csv(path_or_buf=os.path.join(REF_DIR,'snv_sc%d.bed'%(c+1)), sep='\t', header=False, mode='w', index=False)
#
#            gen.write_snv_mtx(snv_mtx = exp_res['snv_mtx'], snv_loc=exp_res['snv_loc'], e=e)


rule gen_before_screads:
    """Generate single-cell reads using dwgsim."""
    input:
        B_FASTA = expand(os.path.join(REF_DIR, "{prototype}_{allele}.fa"), prototype = PROTOTYPES, allele = ALLELES)
    output:
        B_FASTQ_1 = temp(expand(os.path.join(SAMPLE_DIR, "{prototype}_{allele}.bwa.read1.fastq.gz"), prototype = PROTOTYPES, allele = ALLELES)),
        B_FASTQ_2 = temp(expand(os.path.join(SAMPLE_DIR, "{prototype}_{allele}.bwa.read2.fastq.gz"), prototype = PROTOTYPES, allele = ALLELES))
    params:
        stub = expand("{prototype}_{allele}", prototype = PROTOTYPES, allele = ALLELES)
    run:
        from subprocess import call
        for stub in params.stub:
            call("../../src/DWGSIM/dwgsim -e {} -E {} -R 0 -r 0 -o 1 -H -C {} data/scref/{}.fa data/screads/{}".format(PBE1, PBE2, MEAN_COV, stub, stub).split())


rule gen_after_screads:
    """Generate single-cell reads using dwgsim."""
    input:
        A_FASTA = expand(os.path.join(REF_DIR, "{single_cell}_{allele}.fa"), single_cell = SINGLE_CELLS, allele = ALLELES)
    output:
        A_FASTQ_1 = temp(expand(os.path.join(SAMPLE_DIR, "{single_cell}_{allele}.bwa.read1.fastq.gz"), single_cell = SINGLE_CELLS, allele = ALLELES)),
        A_FASTQ_2 = temp(expand(os.path.join(SAMPLE_DIR, "{single_cell}_{allele}.bwa.read2.fastq.gz"), single_cell = SINGLE_CELLS, allele = ALLELES))
    params:
        stub = expand("{single_cell}_{allele}", single_cell = SINGLE_CELLS, allele = ALLELES)
    run:
        from subprocess import call
        for stub in params.stub:
            call("../../src/DWGSIM/dwgsim -e {} -E {} -R 0 -r 0 -o 1 -H -C {} data/scref/{}.fa data/screads/{}".format(PBE1, PBE2, MEAN_COV, stub, stub).split())


rule combine_before_alleles:
    input:
        B_ALLELE_1 = expand(os.path.join(SAMPLE_DIR, "{prototype}_a1.bwa.{read}.fastq.gz"), prototype = PROTOTYPES, read = READS),
        B_ALLELE_2 = expand(os.path.join(SAMPLE_DIR, "{prototype}_a2.bwa.{read}.fastq.gz"), prototype = PROTOTYPES, read = READS)
    output:
        B_COMBINED_ALLELES = temp(expand(os.path.join(SAMPLE_DIR, "{prototype}_a1a2.bwa.{read}.fastq.gz"), prototype = PROTOTYPES, read = READS))
    run:
        from subprocess import call
        for i in range(0, len(input.B_ALLELE_1)):
            call("cat {} {} > {}".format(input.B_ALLELE_1[i], input.B_ALLELE_2[i], output.B_COMBINED_ALLELES[i]), shell = True)


rule create_before_filenames:
    input:
        B_COMBINED_ALLELES = rules.combine_before_alleles.output.B_COMBINED_ALLELES
    output:
        B_FQ_FNAMES = temp(os.path.join(SAMPLE_DIR, "B_filenames.txt"))
    run:
        filenames = glob.glob('data/screads/before*_a1a2*.fastq.gz')
        with open(output.B_FQ_FNAMES, 'w') as f:
            for file in filenames:
                f.write("%s\n" % file)


rule mix_fastq:
    input:
        B_FQ_FNAMES = rules.create_before_filenames.output.B_FQ_FNAMES,
        B_COMBINED_ALLELES = rules.combine_before_alleles.output.B_COMBINED_ALLELES
    output:
        BULK_TOC = os.path.join(BULK_DIR, "bulk_TOC.txt"),
        B_R1 = temp(expand(os.path.join(BULK_DIR, "bulk{n_b}.bwa.read1.fastq.gz"), n_b = N_B)),
        B_R2 = temp(expand(os.path.join(BULK_DIR, "bulk{n_b}.bwa.read2.fastq.gz"), n_b = N_B))
    run:
        import numpy as np
        import json
        from src import mix
        
        BULK_FQ = output.B_R1 + output.B_R2
        with open(output.BULK_TOC, 'w') as TOC:
            for bulk_sample in range(1, 2 * NBulk + 1):
                dist = np.random.dirichlet([0.1 for i in range(0, NPROTO)])
                experiment = {'total_reads': 100000, 'rng_seed': SEED, 'mix_path': BULK_FQ[bulk_sample - 1]}
                TOC.write('Bulk sample {} consists of:\n'.format(bulk_sample))
                with open(input.B_FQ_FNAMES, 'r') as f:
                    for proto in f:
                        num = int(proto.split('_')[3][2:])
                        experiment['sc{}'.format(num)] = {'fraction': dist[num - 1], 'path': proto.strip()}
                        TOC.write('    {}% single cell {}'.format(dist[num - 1] * 100, num))
                experiment = json.dumps(experiment)
                mix.mix_fastq(experiment)


rule combine_after_alleles:
    input:
        A_ALLELE_1 = expand(os.path.join(SAMPLE_DIR, "{single_cell}_a1.bwa.{read}.fastq.gz"), single_cell = SINGLE_CELLS, read = READS),
        A_ALLELE_2 = expand(os.path.join(SAMPLE_DIR, "{single_cell}_a2.bwa.{read}.fastq.gz"), single_cell = SINGLE_CELLS, read = READS),
    output:
        A_COMBINED_ALLELES = temp(expand(os.path.join(SAMPLE_DIR, "{single_cell}_a1a2.bwa.{read}.fastq.gz"), single_cell = SINGLE_CELLS, read = READS)),
    run:
        from subprocess import call
        for i in range(0, len(input.A_ALLELE_1)):
            call("cat {} {} > {}".format(input.A_ALLELE_1[i], input.A_ALLELE_2[i], output.A_COMBINED_ALLELES[i]), shell = True)


rule bwa_idx:
    input:
        _REF = rules.gen_scref.output._REF
    output:
        REF_INDEX = "{input}.bwt"
    shell:
        "bwa index {input}"


rule bwa_map_bulk:
    input:
        REF_INDEX = os.path.join(REF_DIR, "ref_source.fa.bwt"),
        _REF = rules.gen_scref.output._REF,
        B_R1 = rules.mix_fastq.output.B_R1,
        B_R2 = rules.mix_fastq.output.B_R2
    output:
        B_UNSORTED_BAM = temp(expand(os.path.join(BULK_DIR, "bulk{n_b}_.bam"), n_b = N_B))
    threads:
        8
    log:
        expand(os.path.join(LOGS_DIR, "bwa_mem/bulk{n_b}.log"), n_b = N_B)
    run:
        from subprocess import call
        for i in range(0, len(input.B_R1)):
            call("bwa mem -t {} {} {} {} | \nsamtools view -Sb - > {}".format(threads, input._REF, input.B_R1[i], input.B_R2[i], output.B_UNSORTED_BAM[i]), shell = True)


rule bwa_map_after:
    input:
        REF_INDEX = os.path.join(REF_DIR, "ref_source.fa.bwt"),
        _REF = rules.gen_scref.output._REF,
        A_R1 = expand(os.path.join(SAMPLE_DIR, "{single_cell}_a1a2.bwa.read1.fastq.gz"), single_cell = SINGLE_CELLS),
        A_R2 = expand(os.path.join(SAMPLE_DIR, "{single_cell}_a1a2.bwa.read2.fastq.gz"), single_cell = SINGLE_CELLS)
    output:
        A_UNSORTED_BAM = temp(expand(os.path.join(SC_DIR, "{single_cell}_a1a2.bam"), single_cell = SINGLE_CELLS))
    threads:
        8
    log:
        expand(os.path.join(LOGS_DIR, "bwa_mem/{single_cell}.log"), single_cell = SINGLE_CELLS)
    run:
        from subprocess import call
        for i in range(0, len(input.A_R1)):
            call("bwa mem -t {} {} {} {} | \nsamtools view -Sb - > {}".format(threads, input._REF, input.A_R1[i], input.A_R2[i], output.A_UNSORTED_BAM[i]), shell = True)


rule samtools_sort_bulk:
    input:
        B_UNSORTED_BAM = rules.bwa_map_bulk.output.B_UNSORTED_BAM
    output:
        B_SORTED_BAM = expand(os.path.join(BULK_DIR, "bulk{n_b}.bam"), n_b = N_B)
    params:
        stub = expand(os.path.join(BULK_DIR, "bulk{n_b}"), n_b = N_B)
    run:
        from subprocess import call
        for i in range(0, len(input.B_UNSORTED_BAM)):
            call("samtools sort -T {} -O bam {} > {}".format(params.stub[i], input.B_UNSORTED_BAM[i], output.B_SORTED_BAM[i]), shell = True)


rule samtools_sort_after:
    input:
        A_UNSORTED_BAM = rules.bwa_map_after.output.A_UNSORTED_BAM
    output:
        A_SORTED_BAM = expand(os.path.join(SC_DIR, "{single_cell}.bam"), single_cell = SINGLE_CELLS)
    params:
        stub = expand(os.path.join(SC_DIR, "{single_cell}"), single_cell = SINGLE_CELLS)
    run:
        from subprocess import call
        for i in range(0, len(input.A_UNSORTED_BAM)):
            call("samtools sort -T {} -O bam {} > {}".format(params.stub[i], input.A_UNSORTED_BAM[i], output.A_SORTED_BAM[i]), shell = True)


rule samtools_index_bulk:
    input:
        B_SORTED_BAM = rules.samtools_sort_bulk.output.B_SORTED_BAM
    output:
        B_BAM_IDX = expand(os.path.join(BULK_DIR, "bulk{n_b}.bam.bai"), n_b = N_B)
    shell:
        "samtools index {input.B_SORTED_BAM}"


rule samtools_index_after:
    input:
        A_SORTED_BAM = rules.samtools_sort_after.output.A_SORTED_BAM
    output:
        A_BAM_IDX = os.path.join(SC_DIR, "{single_cell}.bam.bai")
    shell:
        "samtools index {input.A_SORTED_BAM}"


rule make_bulk_bam_filenames:
    input:
        B_SORTED_BAM = rules.samtools_sort_bulk.output.B_SORTED_BAM
    output:
        B_BAM_FNAMES = temp(os.path.join(BULK_DIR, "bulk_filenames.txt"))
    run:
        filenames = glob.glob(os.path.join(BULK_DIR, "*.bam"))
        with open(output.B_BAM_FNAMES, "w") as f:
            for file in filenames:
                f.write("%s\n" % file)


rule make_after_bam_filenames:
    input:
        A_SORTED_BAM = rules.samtools_sort_after.output.A_SORTED_BAM
    output:
        A_BAM_FNAMES = temp(os.path.join(SC_DIR, "SC_filenames.txt"))
    run:
        filenames = glob.glob(os.path.join(SC_DIR, "*.bam"))
        with open(output.A_BAM_FNAMES, "w") as f:
            for file in filenames:
                f.write("%s\n" % file)


rule make_all_flags:
    input:
        SNV_FLAGS = rules.gen_scref.output.SNV_FLAGS
    output:
        ALL_FLAGS = os.path.join(REF_DIR, "all_flags.csv")
    shell:
        "python src/md2csv-flags.py {input.SNV_FLAGS} {REF_DIR}"


rule monovar_bulk_call:
    input:
        B_BAM_FNAMES = rules.make_bulk_bam_filenames.output.B_BAM_FNAMES,
        B_SORTED_BAM = rules.samtools_sort_bulk.output.B_SORTED_BAM
    output:
        B_CALLS = os.path.join(CALLS_DIR, "monovar/all_bulk.vcf")
    log:
        B_LOGS = os.path.join(LOGS_DIR, "monovar/all_bulk.log")
    shell:
        "source src/monovar_wrapper.sh {REF} {input.B_BAM_FNAMES} {output.B_CALLS}"


rule monovar_after_call:
    input:
        A_BAM_FNAMES = rules.make_after_bam_filenames.output.A_BAM_FNAMES,
        A_SORTED_BAM = rules.samtools_sort_after.output.A_SORTED_BAM
    output:
        A_CALLS = os.path.join(CALLS_DIR, "monovar/all_after.vcf")
    log:
        A_LOGS = os.path.join(LOGS_DIR, "monovar/all_after.log")
    shell:
        "source src/monovar_wrapper.sh {REF} {input.A_BAM_FNAMES} {output.A_CALLS}"


rule bcftools_bulk_call:
    input:
        B_SORTED_BAM = rules.samtools_sort_bulk.output.B_SORTED_BAM
    output:
        B_CALLS = expand(os.path.join(CALLS_DIR, "bcftools/bulk{n_b}.vcf"), n_b = N_B)
    log:
        B_LOGS = expand(os.path.join(LOGS_DIR, "bcftools/bulk{n_b}.log"), n_b = N_B)
    run:
        from subprocess import call
        for i in range(0, len(input.B_SORTED_BAM)):
            call("samtools mpileup -g -f {} {} | bcftools call -mv - > {} 2> {}".format(REF, input.B_SORTED_BAM[i], output.B_CALLS[i], log.B_LOGS[i]), shell = True)


rule bcftools_after_call:
    input:
        A_SORTED_BAM = rules.samtools_sort_after.output.A_SORTED_BAM
    output:
        A_CALLS = expand(os.path.join(CALLS_DIR, "bcftools/{single_cell}.vcf"), single_cell = SINGLE_CELLS)
    log:
        A_LOGS = expand(os.path.join(LOGS_DIR, "bcftools/{single_cell}.log"), single_cell = SINGLE_CELLS)
    run:
        from subprocess import call
        for i in range(0, len(input.A_SORTED_BAM)):
            call("samtools mpileup -g -f {} {} | bcftools call -mv - > {} 2> {}".format(REF, input.A_SORTED_BAM[i], output.A_CALLS[i], log.A_LOGS[i]), shell = True)
