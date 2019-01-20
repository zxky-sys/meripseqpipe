#!/usr/bin/env nextflow 

/*
========================================================================================
                            m6APipe
========================================================================================
 * m6Apipe
 * Homepage / Documentation

 */

/*
 * to be added
 *
 * Authors:
 * Qi Zhao <zhaoqi@sysucc.org.cn>: design and implement the pipeline.
 * Zhu Kaiyu
 */



//pre-defined functions for render command
//=======================================================================================
ANSI_RESET = "\u001B[0m";
ANSI_BLACK = "\u001B[30m";
ANSI_RED = "\u001B[31m";
ANSI_GREEN = "\u001B[32m";
ANSI_YELLOW = "\u001B[33m";
ANSI_BLUE = "\u001B[34m";
ANSI_PURPLE = "\u001B[35m";
ANSI_CYAN = "\u001B[36m";
ANSI_WHITE = "\u001B[37m";
def print_red = {  str -> ANSI_RED + str + ANSI_RESET }
def print_black = {  str -> ANSI_BLACK + str + ANSI_RESET }
def print_green = {  str -> ANSI_GREEN + str + ANSI_RESET }
def print_yellow = {  str -> ANSI_YELLOW + str + ANSI_RESET }
def print_blue = {  str -> ANSI_BLUE + str + ANSI_RESET }
def print_cyan = {  str -> ANSI_CYAN + str + ANSI_RESET }
def print_purple = {  str -> ANSI_PURPLE + str + ANSI_RESET }
def print_white = {  str -> ANSI_WHITE + str + ANSI_RESET }

def helpMessage() {
    log.info"""
    =========================================
     nf-core/m6Apipe v${workflow.manifest.version}
    =========================================
    Usage:

    The typical command for running the pipeline is as follows:

    nextflow path/to/m6APipe/main.nf --readPaths './data/' -profile standard,docker

    Mandatory arguments:
      --readreadPaths               Path to input data (must be surrounded with quotes)
      --genome                      Name of iGenomes reference
      --designfile                  format:filename,control_or_treated,ip_or_input,tag_id
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: standard, conda, docker, singularity, awsbatch, test

    Options:
      --inputformat                 fastq.gz;fastq default = fastq
      --singleEnd                   Specifies that the input is single end reads
      --skip_tophat2 
      --skip_hisat2 
      --skip_bwa
      --skip_star 

    References                      If not specified in the configuration file or you wish to overwrite any of the references.
      --fasta                       Path to Fasta reference
      --gtf                         Path to GTF reference
    
    Other options:
      --outdir                      The output directory where the results will be saved, defalut = $baseDir/results
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

// Show help emssage
if (params.help){
    helpMessage()
    exit 0
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Configurable variables
params.name = false
params.project = false
params.genome = false

//params.reads = "$baseDir/data/*{input,ip}.read1_clean.fastq.gz"
params.fasta = "$baseDir/Genome/hg38/hg38_genome.fa"
params.gtf = "$baseDir/Genome/hg38/hg38_genes.gtf"
params.gff = false
params.bed12 = false
params.designfile = false
params.call = false
params.bowtie_index = false
params.tophat2_index = "/home/zky/m6apipe/results/Genome/Tophat2Index/*"
params.hisat2_index = false
params.bwa_index = "/home/zky/m6apipe/results/Genome/BWAIndex/*"
params.star_index = false
params.email = false
params.plaintext_email = false
params.seqCenter = false

unstrand = params.unstrand ? true : false

// Preset trimming options
params.pico = false
if (params.pico){
    clip_r1 = 3
    clip_r2 = 0
    three_prime_clip_r1 = 0
    three_prime_clip_r2 = 3
    forward_stranded = true
    reverse_stranded = false
    unstranded = false
}

// Validate inputs

if ( params.fasta ){
    fasta = file(params.fasta)
    if( !fasta.exists() ) exit 1, print_red("Fasta file not found: ${params.fasta}")
}
else {
    exit 1, print_red("No reference genome specified!")
}
if( params.gtf ){
    gtf = file ( params.gtf )
    if( !gtf.exists() ) exit 1, print_red("gtf not found: ${params.gtf}")
} else {
    exit 1, print_red("No GTF annotation specified!")
}
if( params.designfile ) {
    designfile = file(params.designfile)
    if( !designfile.exists() ) exit 1, print_red("Design file not found: ${params.designfile}")
}else{
    exit 1, print_red("No Design file specified!")
}

/*
 * Create a channel for input read files
 */
if(params.readPaths){
    Channel
        .fromFilePairs( "$params.readPaths/*", size: params.singleEnd ? 1 : 2 ) 
        //.map { row -> [ row[0], [file(row[1][0])]] }
        .ifEmpty { exit 1, print_red( "params.readPaths was empty - no input files supplied" )}
        //.subscribe { println it }
        .set { raw_reads_fastqc }
}
/*
========================================================================================
                             check or build the index
========================================================================================
*/ 
/*
 * PREPROCESSING - Build BED12 file
 * NEED gtf.file
 */
if(params.gtf && !params.bed12){
    process makeBED12 {
        tag "gtf2bed12"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/reference_genome" : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'

        input:
        file gtf
        
        output:
        file "${gtf.baseName}.bed" into bed_rseqc, bed_genebody_coverage

        script:      
        """
        bash ${baseDir}/bin/gtf2bed12.sh $gtf
        """        
    }
}

/*
 * PREPROCESSING - Build TOPHAT2 index
 * NEED genome.fa
 */
if( params.tophat2_index ){
    tophat2_index = Channel
        .fromPath(params.tophat2_index)
        .ifEmpty { exit 1, "STAR index not found: ${params.tophat2_index}" }
}else if( params.fasta ){
    process MakeTophat2Index {
        tag "tophat2_index"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/ ": params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'
        input:
        file fasta

        output:
        file "Tophat2Index/*" into tophat2_index

        when:
        !params.skip_tophat2

        script:
        tophat2_index = "Tophat2Index/" + fasta.baseName.toString()
        """
        mkdir Tophat2Index
        bowtie2-build -p ${task.cpus} -f $params.fasta $tophat2_index
        """
    }
}else {
    exit 1, print_red("There is no Tophat2 Index")
}

/*
 * PREPROCESSING - Build HISAT2 index
 * NEED genome.fa genes.gtf snp.txt/vcf
 */
if( params.hisat2_index ){
    hisat2_index = Channel
        .fromPath(params.hisat2_index)
        .ifEmpty { exit 1, "hisat2 index not found: ${params.hisat2_index}" }
}else if( params.fasta ){
    process MakeHisat2Index {
        tag "hisat2_index"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/ " : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'        
        input:
        file fasta
        file gtf

        output:
        file "Hisat2Index/*" into hisat2_index

        when:
        !params.skip_hisat2
        
        script:
        """
        mkdir Hisat2Index
        hisat2_extract_exons.py $gtf > Hisat2Index/${gtf.baseName}.exon
        hisat2_extract_splice_sites.py $gtf > Hisat2Index/${gtf.baseName}.ss
        hisat2-build -p ${task.cpus} -f $fasta --exon Hisat2Index/${gtf.baseName}.exon --ss Hisat2Index/${gtf.baseName}.ss Hisat2Index/${fasta.baseName}
        """
    }
}else {
    exit 1, print_red("There is no Hisat2 Index")
}

/*
 * PREPROCESSING - Build BWA index
 * NEED genome.fa
 */
if( params.bwa_index ){
    bwa_index = Channel
        .fromPath(params.bwa_index)
        .ifEmpty { exit 1, "bwa index not found: ${params.bwa_index}" }
}else if(params.fasta ){
    process MakeBWAIndex {
        tag "bwa_index"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/" : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'

        input:
        file fasta

        output:
        file "BWAIndex/*" into bwa_index

        when:
        !params.skip_bwa
     
        script:
        """
        mkdir BWAIndex
        cd BWAIndex/
        bwa index -t ${task.cpus} -p ${fasta.baseName} -abwtsw ../$fasta
        cd ../
        """
    }
}else {
    exit 1, print_red("There is no BWA Index")
}

/*
 * PREPROCESSING - Build STAR index
 * NEED genome.fa genes.gtf
 */
if( params.star_index ){
    star_index = Channel
        .fromPath(params.star_index)
        .ifEmpty { exit 1, "STAR index not found: ${params.star_index}" }
}else if( params.fasta ){
    process MakeStarIndex {
        tag "star_index"
        publishDir path: { params.saveReference ? "${params.outdir}/Genome/" : params.outdir },
                   saveAs: { params.saveReference ? it : null }, mode: 'copy'
        input:
        file fasta
        file gtf

        output:
        file "StarIndex" into star_index

        when:
        !params.skip_star 

        script:
        readLength = 50
        overhang = readLength - 1
        """
        STAR --runThreadN ${task.cpus} \\
        --runMode genomeGenerate \\
        --genomeDir StarIndex \\
        --genomeFastaFiles $fasta \\
        --sjdbGTFfile $gtf \\
        --sjdbOverhang $Overhang \\
        """
    }

}else {
   exit 1, print_red("There is no STAR Index")
}
/*
========================================================================================
                                Step 1. QC------FastQC
========================================================================================
*/ 
process Fastqc{
    tag "$sample_name"
    publishDir "${params.outdir}/fastqc", mode: 'link', overwrite: true

    input:
    set sample_name, file(reads) from raw_reads_fastqc
    file designfile

    output:
    set sample_name, file("*.fastq") into  tophat2_reads , hisat2_reads , bwa_reads , star_reads
    file "fastqc/*" into fastq_results

    when:
    !params.skip_fastqc

    script:
    if (params.singleEnd) {
        filename = reads.toString() - ~/(_trimmed)?(_val_1)?(_Clean)?(_[0-9])?(\.fq)?(\.fastq)?(\.gz)?$/
        sample_name = filename
        whether_unzip = (params.inputformat == "fastq") ? "" : "gzip -fd $reads"
        """
        $whether_unzip
        bash $baseDir/bin/rename_and_fastqc.sh $designfile $filename
        """
    } else {
        filename = reads[0].toString() - ~/(_trimmed)?(_val_1)?(_Clean)?(_[0-9])?(\.fq)?(\.fastq)?(\.gz)?$/
        sample_name = filename
        whether_unzip = (params.inputformat == "fastq") ? "" : "gzip -fd ${reads[0]} ${reads[1]}" 
        """
        $whether_unzip
        bash $baseDir/bin/rename_and_fastqc.sh $designfile $filename        
        """
    }
}
/*
========================================================================================
                            Step 2. Reads Mapping
========================================================================================
*/ 
process Tophat2Align {
    tag "$sample_name"
    publishDir "${params.outdir}/aligners/tophat2", mode: 'link', overwrite: true

    input:
    set sample_name, file(reads) from tophat2_reads
    file index from tophat2_index.collect()
    file gtf

    output:
    file "*_tophat2.bam" into tophat2_bam
    
    when:
    !params.skip_tophat2

    script:
    index_base = index[0].toString() - ~/(\.rev)?(\.\d)?(\.bt2)?$/
    strand_str = unstrand ? "fr-unstranded" : "fr-firststrand"
    if (params.singleEnd) {
        """
        tophat  -p ${task.cpus} \\
                -G $gtf \\
                -o $sample_name \\
                --library-type $strand_str \\
                $index_base \\
                $reads 
        mv $sample_name/accepted_hits.bam ${reads.baseName}_tophat2.bam
        """
    } else {
        """
        tophat -p ${task.cpus} \\
                -G $gtf \\
                -o $sample_name \\
                --library-type $strand_str \\
                $index_base \\
                ${reads[0]} ${reads[1]}
        mv $sample_name/accepted_hits.bam ${reads[0].baseName}_tophat2.bam
        """
    }
}

process Hisat2Align {
    tag "$sample_name"
    publishDir "${params.outdir}/aligners/hisat2", mode: 'link', overwrite: true

    input:
    set sample_name, file(reads) from hisat2_reads
    file index from hisat2_index.collect()

    output:
    file "*_hisat2.bam" into hisat2_bam

    when:
    !params.skip_hisat2

    script:
    index_base = index[0].toString() - ~/(\.exon)?(\.\d)?(\.ht2)?$/
    if (params.singleEnd) {
        """
        hisat2  -p ${task.cpus} --dta\\
                -x $index_base \\
                -U $reads \\
                -S ${reads.baseName}_hisat2.sam 2> ${reads.baseName}_hisat2_summary.txt
        samtools view -bS ${reads.baseName}_hisat2.sam > ${reads.baseName}_hisat2.bam
        """
    } else {
        """
        hisat2  -p ${task.cpus} --dta\\
                -x $index_base \\
                -1 ${reads[0]} -2 ${reads[1]} \\
                -S ${reads[0].baseName}_hisat2.sam 2> ${reads[0].baseName}_hisat2_summary.txt
        samtools view -bS ${reads[0].baseName}_hisat2.sam > ${reads[0].baseName}_hisat2.bam
        """
        }
}

process BWAAlign{
    tag "$sample_name"
    publishDir "${params.outdir}/aligners/bwa", mode: 'link', overwrite: true
    
    input:
    set sample_name, file(reads) from bwa_reads
    file index from bwa_index.collect()

    output:
    file "*_bwa.bam" into bwa_bam

    when:
    !params.skip_bwa

    script:
    index_base = index[0].toString() - ~/(\.pac)?(\.bwt)?(\.ann)?(\.amb)?(\.sa)?(\.fa)?$/
    if (params.singleEnd) {
        """
        bwa aln -t ${task.cpus} \\
                -f ${reads.baseName}.sai \\
                $index_base \\
                $reads
        bwa samse -f ${reads.baseName}_bwa.sam \\
                $index_base \\
                ${reads.baseName}.sai \\
                $reads
        samtools view -h -bS ${reads.baseName}_bwa.sam > ${reads.baseName}_bwa.bam
        """
    } else {
        """
        bwa aln -t ${task.cpus} \\
                -f ${reads[0].baseName}.sai \\
                $index_base \\
                ${reads[0]}
        bwa aln -t ${task.cpus} \\
                -f ${reads[1].baseName}.sai \\
                $index_base \\
                ${reads[1]}
        bwa sampe -f ${reads[0].baseName}_bwa.sam \\
                $index_base \\
                ${reads[0].baseName}.sai ${reads[0].baseName}.sai \\
                ${reads[0]} ${reads[1]}
        samtools view -h -bS ${reads[0].baseName}_bwa.sam > ${reads[0].baseName}_bwa.bam
        """
    }
}

process StarAlign {
    tag "$sample_name"
    publishDir "${params.outdir}/aligners/star", mode: 'link', overwrite: true
    
    input:
    set sample_name, file(reads) from star_reads
    file star_index from star_index.collect()

    output:
    file "*_star.bam" into star_bam

    when:
    !params.skip_star

    script:
    if (params.singleEnd) {
        """
        STAR --runThreadN ${task.cpus} \\
            --twopassMode Basic \\
            --genomeDir $star_index \\
            --readFilesIn $reads  \\
            --outSAMtype BAM Unsorted \\
            --outFileNamePrefix ${reads.baseName} 
        mv ${reads.baseName}Aligned.out.bam > ${reads.baseName}_star.bam
        """
    } else {
        """
        STAR --runThreadN ${task.cpus} \\
            --twopassMode Basic \\
            --genomeDir $star_index \\
            --readFilesIn ${reads[0]} ${reads[1]}  \\
            --outSAMtype BAM Unsorted \\
            --outFileNamePrefix ${reads[0].baseName}
        mv ${reads[0].baseName}Aligned.out.bam > ${reads[0].baseName}_star.bam
        """
    }
}
/*
========================================================================================
                        Step 3 Sort BAM file AND QC
========================================================================================
*/ 
Channel
    .from()
    .concat(tophat2_bam, hisat2_bam, bwa_bam, star_bam)
    .into {merge_bam_file; test_channel1}
test_channel1.subscribe{ println it }
/*
 * STEP 3-1 - Sort BAM file
*/
process Sort {
    publishDir "${params.outdir}/samtools_sort/", mode: 'link', overwrite: true
    input:
    file( bam_query_file ) from merge_bam_file.collect()
    file designfile  // designfile:filename,control_treated,input_ip

    output:
    file "*_sort*" into exomepeak_bam, macs2_bam, metpeak_bam, metdiff_bam, 
                        htseq_count_bam, rseqc_bam, genebody_bam, diffexomepeak_bam,
                        cufflinks_bam

    script:
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """ 
    cat $designfile > tmp_designfile.txt 
    dos2unix tmp_designfile.txt     
    if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/samtools_sort.sh tophat2 ; fi &
    if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/samtools_sort.sh hisat2 ; fi &
    if [ $skip_bwa == "false" ]; then bash $baseDir/bin/samtools_sort.sh bwa ; fi &
    if [ $skip_star == "false" ]; then bash $baseDir/bin/samtools_sort.sh star ; fi &
    """
}
/*
 * STEP 3-2 - RSeQC analysis
*/
process RSeQC {
    publishDir "${params.outdir}/RSeQC" , mode: 'copy', overwrite: true,
        saveAs: {filename ->
                 if (filename.indexOf("bam_stat.txt") > 0)                      "bam_stat/$filename"
            else if (filename.indexOf("infer_experiment.txt") > 0)              "infer_experiment/$filename"
            else if (filename.indexOf("read_distribution.txt") > 0)             "read_distribution/$filename"
            else if (filename.indexOf("read_duplication.DupRate_plot.pdf") > 0) "read_duplication/$filename"
            else if (filename.indexOf("read_duplication.DupRate_plot.r") > 0)   "read_duplication/rscripts/$filename"
            else if (filename.indexOf("read_duplication.pos.DupRate.xls") > 0)  "read_duplication/dup_pos/$filename"
            else if (filename.indexOf("read_duplication.seq.DupRate.xls") > 0)  "read_duplication/dup_seq/$filename"
            else if (filename.indexOf("RPKM_saturation.eRPKM.xls") > 0)         "RPKM_saturation/rpkm/$filename"
            else if (filename.indexOf("RPKM_saturation.rawCount.xls") > 0)      "RPKM_saturation/counts/$filename"
            else if (filename.indexOf("RPKM_saturation.saturation.pdf") > 0)    "RPKM_saturation/$filename"
            else if (filename.indexOf("RPKM_saturation.saturation.r") > 0)      "RPKM_saturation/rscripts/$filename"
            else if (filename.indexOf("inner_distance.txt") > 0)                "inner_distance/$filename"
            else if (filename.indexOf("inner_distance_freq.txt") > 0)           "inner_distance/data/$filename"
            else if (filename.indexOf("inner_distance_plot.r") > 0)             "inner_distance/rscripts/$filename"
            else if (filename.indexOf("inner_distance_plot.pdf") > 0)           "inner_distance/plots/$filename"
            else if (filename.indexOf("junction_plot.r") > 0)                   "junction_annotation/rscripts/$filename"
            else if (filename.indexOf("junction.xls") > 0)                      "junction_annotation/data/$filename"
            else if (filename.indexOf("splice_events.pdf") > 0)                 "junction_annotation/events/$filename"
            else if (filename.indexOf("splice_junction.pdf") > 0)               "junction_annotation/junctions/$filename"
            else if (filename.indexOf("junctionSaturation_plot.pdf") > 0)       "junction_saturation/$filename"
            else if (filename.indexOf("junctionSaturation_plot.r") > 0)         "junction_saturation/rscripts/$filename"
            else filename
        }    
    when:
    !params.skip_qc && !params.skip_rseqc

    input:
    file bam_rseqc from rseqc_bam
    file bed12 from bed_rseqc.collect()

    output:
    file "*.{txt,pdf,r,xls}" into rseqc_results
    
    script:
    /* 
    def strandRule = ''
    if (forward_stranded && !unstranded){
        strandRule = params.singleEnd ? '-d ++,--' : '-d 1++,1--,2+-,2-+'
    } else if (reverse_stranded && !unstranded){
        strandRule = params.singleEnd ? '-d +-,-+' : '-d 1+-,1-+,2++,2--'
    }
    */
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/rseqc.sh tophat2 $bed12 ; fi &
    if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/rseqc.sh hisat2 $bed12 ; fi &
    if [ $skip_bwa == "false" ]; then bash $baseDir/bin/rseqc.sh bwa $bed12 ; fi &
    if [ $skip_star == "false" ]; then bash $baseDir/bin/rseqc.sh star $bed12 ; fi &
    """
}

process CreateBigWig {
    publishDir "${params.outdir}/rseqc/bigwig", mode: 'link', overwrite: true

    when:
    !params.skip_qc && !params.skip_genebody_coverage  

    input:
    file bam from genebody_bam

    output:
    file "*.bigwig" into bigwig_for_genebody

    script:
    '''
    for bam_file in *.bam
    do
        bamCoverage -b $bam_file -o ${bam_file%.bam*}.bigwig
    done
    '''
}

process GenebodyCoverage {
       publishDir "${params.outdir}/rseqc" , mode: 'link', overwrite: true, 
        saveAs: {filename ->
            if (filename.indexOf("geneBodyCoverage.curves.pdf") > 0)       "geneBodyCoverage/$filename"
            else if (filename.indexOf("geneBodyCoverage.r") > 0)           "geneBodyCoverage/rscripts/$filename"
            else if (filename.indexOf("geneBodyCoverage.txt") > 0)         "geneBodyCoverage/data/$filename"
            else if (filename.indexOf("log.txt") > -1) false
            else filename
        }

    when:
    !params.skip_qc && !params.skip_genebody_coverage

    input:
    file bigwig from bigwig_for_genebody
    file bed12 from bed_genebody_coverage.collect()

    output:
    file "*.{txt,pdf,r}" into genebody_coverage_results

    shell:
    '''
    for bigwig_file in *.bigwig
    do
        geneBody_coverage2.py -i $bigwig_file -o ${bigwig_file%.bigwig*}.rseqc.txt -r !{bed12}
    done
    '''
}

/*
========================================================================================
                            Step 4 Peak Calling
========================================================================================
*/ 
/*
 * STEP 4 - 1  Peak Calling------ExomePeak, MetPeak, MACS2
*/
process Exomepeak {
    publishDir "${params.outdir}/peak_calling/exomepeak", mode: 'link', overwrite: true

    input:
    file bam_bai_file from exomepeak_bam
    file gtf
    file designfile

    output:
    file "*" into exomepeak_results
    file "exomePeak*.bed" into exomepeak_bed
    
    when:
    true

    script:  
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    if [ $skip_tophat2 == "false" ]; 
        then Rscript $baseDir/bin/exomePeak.R tophat2 ;
        fi &
    if [ $skip_hisat2 == "false" ]; 
        then Rscript $baseDir/bin/exomePeak.R hisat2 ;
        fi &
    if [ $skip_bwa == "false" ]; 
        then Rscript $baseDir/bin/exomePeak.R bwa ;
        fi &
    if [ $skip_star == "false" ]; 
        then Rscript $baseDir/bin/exomePeak.R star ;
        fi &
    """
}

process Metpeak {
    publishDir "${params.outdir}/peak_calling/metpeak", mode: 'link', overwrite: true

    input:
    file bam_bai_file from metpeak_bam
    file gtf
    file designfile

    output:
    file "*" into metpeak_results
    file "metpeak*.bed" into metpeak_bed

    when:
    true

    script:  
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    if [ $skip_tophat2 == "false" ]; 
        then Rscript $baseDir/bin/MeTPeak.R tophat2 ;
        fi &
    if [ $skip_hisat2 == "false" ]; 
        then Rscript $baseDir/bin/MeTPeak.R hisat2 ;
        fi &
    if [ $skip_bwa == "false" ]; 
        then Rscript $baseDir/bin/MeTPeak.R bwa ;
        fi &
    if [ $skip_star == "false" ]; 
        then Rscript $baseDir/bin/MeTPeak.R star ;
        fi &
    """
}

process Macs2{
    publishDir "${params.outdir}/peak_calling/macs2", mode: 'link', overwrite: true

    input:
    file bam_bai_file from macs2_bam
    file designfile

    output:
    file "macs2*" into macs2_results
    file "*/*.bed" into macs2_bed

    when:
    true

    script:
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    cat designfile.txt > tmp_designfile.txt
    dos2unix tmp_designfile.txt
    if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/macs2.sh tophat2 ; fi &
    if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/macs2.sh hisat2 ; fi &
    if [ $skip_bwa == "false" ]; then bash $baseDir/bin/macs2.sh bwa ; fi &
    if [ $skip_star == "false" ]; then bash $baseDir/bin/macs2.sh star ; fi &
    """
}
/*
 * STEP 4 - 2 Differential methylation analysis------ExomePeak, MetPeak, QNB, MATK
*/
process DiffExomepeak {
    publishDir "${params.outdir}/peak_diff/diffexomepeak", mode: 'link', overwrite: true

    input:
    file bam_bai_file from diffexomepeak_bam
    file gtf
    file designfile

    output:
    file "*" into diffexomepeak_results
    file "diffexomePeak*.bed" into diffexomepeak_bed
    
    when:
    true

    script:  
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    if [ $skip_tophat2 == "false" ]; 
        then Rscript $baseDir/bin/diffexomePeak.R tophat2 ;
        fi &
    if [ $skip_hisat2 == "false" ]; 
        then Rscript $baseDir/bin/diffexomePeak.R hisat2 ;
        fi &
    if [ $skip_bwa == "false" ]; 
        then Rscript $baseDir/bin/diffexomePeak.R bwa ;
        fi &
    if [ $skip_star == "false" ]; 
        then Rscript $baseDir/bin/diffexomePeak.R star ;
        fi &
    """
}

process Metdiff {
    publishDir "${params.outdir}/peak_diff/metdiff", mode: 'link', overwrite: true

    input:
    file bam_bai_file from metdiff_bam
    file gtf
    file designfile

    output:
    file "*" into metdiff_results
    file "metdiff*.bed" into metdiff_bed
    
    when:
    true

    script:  
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    if [ $skip_tophat2 == "false" ]; 
        then Rscript $baseDir/bin/MeTDiff.R tophat2 ;
        fi &
    if [ $skip_hisat2 == "false" ]; 
        then Rscript $baseDir/bin/MeTDiff.R hisat2 ;
        fi &
    if [ $skip_bwa == "false" ]; 
        then Rscript $baseDir/bin/MeTDiff.R bwa ;
        fi &
    if [ $skip_star == "false" ]; 
        then Rscript $baseDir/bin/MeTDiff.R star ;
        fi &
    """
}

process Htseq_count{
    publishDir "${params.outdir}/diff_expr/htseq_count", mode: 'link', overwrite: true

    input:
    file bam_bai_file from htseq_count_bam
    file gtf

    output:
    file "*input*.count" into htseq_count_input_to_QNB, htseq_count_input_to_deseq2, htseq_count_input_to_edgeR
    file "*ip*.count" into htseq_count_ip_to_QNB

    when:
    true

    script:
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    if [ $skip_tophat2 == "false" ]; 
        then bash $baseDir/bin/htseq_count_input.sh tophat2 $gtf ; 
             bash $baseDir/bin/htseq_count_ip.sh tophat2 $gtf ;
             Rscript $baseDir/bin/get_htseq_matrix.R tophat2 ;
        fi &
    if [ $skip_hisat2 == "false" ]; 
        then bash $baseDir/bin/htseq_count_input.sh hisat2 $gtf ; 
             bash $baseDir/bin/htseq_count_ip.sh hisat2 $gtf ;
             Rscript $baseDir/bin/get_htseq_matrix.R hisat2 ;
        fi &
    if [ $skip_bwa == "false" ]; 
        then bash $baseDir/bin/htseq_count_input.sh bwa $gtf ; 
             bash $baseDir/bin/htseq_count_ip.sh bwa $gtf ;
             Rscript $baseDir/bin/get_htseq_matrix.R bwa ;
        fi &
    if [ $skip_star == "false" ]; 
        then bash $baseDir/bin/htseq_count_input.sh star $gtf ; 
             bash $baseDir/bin/htseq_count_ip.sh star $gtf ;
             Rscript $baseDir/bin/get_htseq_matrix.R star ;
        fi &
    """
}

process QNB {
    publishDir "${params.outdir}/peak_diff/QNB", mode: 'link', overwrite: true

    input:
    file reads_count_input from htseq_count_input_to_QNB
    file reads_count_ip from htseq_count_ip_to_QNB

    output:
    file "*" into qnb_results
    
    when:
    true

    script:  
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    if [ $skip_tophat2 == "false" ]; 
        then Rscript $baseDir/bin/QNB.R tophat2 ;
        fi &
    if [ $skip_hisat2 == "false" ]; 
        then Rscript $baseDir/bin/QNB.R hisat2 ;
        fi &
    if [ $skip_bwa == "false" ]; 
        then Rscript $baseDir/bin/QNB.R bwa ;
        fi &
    if [ $skip_star == "false" ]; 
        then Rscript $baseDir/bin/QNB.R star ;
        fi &
    """
}
/*
========================================================================================
                        Step 5 Merge Peak AND Peak Visualization
========================================================================================
*/
/*
 * STEP 5-1 Merge Peak
*/
Channel
    .from()
    .concat(exomepeak_bed, metpeak_bed, macs2_bed)
    .into {merge_bed_peak_file; test_channel3}

Channel
    .from()
    .concat(diffexomepeak_bed, metdiff_bed)
    .into {merge_bed_diffpeak_file; test_channel4}

process PeakMergeBYBed {
    publishDir "${params.outdir}/merge/", mode: 'link', overwrite: true
    
    input:
    file peak_bed from merge_bed_peak_file.collect()
    file designfile

    output:
    file "*/ConsensusPeaks.bed" into merge_bed

    when:
    true

    shell:
    mspc_dir = baseDir + "/bin/mspc_v3.3/*"
    '''
    ln -s !{mspc_dir} ./
    ls exomePeak*.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r bio -w 1E-4 -s 1E-8"}' | bash
    ls metpeak*.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r bio -w 1E-4 -s 1E-8"}' | bash
    for bed in */*.bed
    do
        mv $bed ${bed/%ConsensusPeaks.bed/temp.bed}
    done
    ls */*.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r bio -w 1E-4 -s 1E-8"}' | bash
    '''
}

process DiffPeakMergeBYBed {
    publishDir "${params.outdir}/merge/", mode: 'link', overwrite: true
    
    input:
    file peak_bed from merge_bed_diffpeak_file.collect()
    file designfile

    output:
    file "*/*.bed" into diffmerge_bed

    when:
    false

    shell:
    mspc_dir = baseDir + "/bin/mspc_v3.3/*"
    '''
    ln -s !{mspc_dir} ./
    ls diffexomePeak*.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r bio -w 1E-4 -s 1E-8"}' | bash
    ls metdiff*.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r bio -w 1E-4 -s 1E-8"}' | bash
    for bed in */*.bed
    do
        mv $bed abc.bed
    done
    ls */*.bed | awk '{ORS=" "}{print "-i",$0}'| awk '{print "dotnet CLI.dll",$0,"-r bio -w 1E-4 -s 1E-8"}' | bash
    '''
}

/*
========================================================================================
                        Step X Differential expression analysis
========================================================================================
*/
process Deseq2{
    publishDir "${params.outdir}/diff_expr/deseq2", mode: 'link', overwrite: true

    input:
    file reads_count_input from htseq_count_input_to_deseq2

    output:
    file "*.csv" into deseq2_results
    
    when:
    true

    script:
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    if [ $skip_tophat2 == "false" ]; 
        then Rscript $baseDir/bin/DESeq2.R tophat2 ;
        fi &
    if [ $skip_hisat2 == "false" ]; 
        then Rscript $baseDir/bin/DESeq2.R hisat2 ;
        fi &
    if [ $skip_bwa == "false" ]; 
        then Rscript $baseDir/bin/DESeq2.R bwa ;
        fi &
    if [ $skip_star == "false" ]; 
        then Rscript $baseDir/bin/DESeq2.R star ;
        fi &
    """
}

process EdgeR{
    publishDir "${params.outdir}/diff_expr/edgeR", mode: 'link', overwrite: true

    input:
    file reads_count_input from htseq_count_input_to_edgeR

    output:
    //file "*.csv" into edgeR_results
    
    when:
    true

    script:
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    if [ $skip_tophat2 == "false" ]; 
        then Rscript $baseDir/bin/edgeR.R tophat2 ;
        fi &
    if [ $skip_hisat2 == "false" ]; 
        then Rscript $baseDir/bin/edgeR.R hisat2 ;
        fi &
    if [ $skip_bwa == "false" ]; 
        then Rscript $baseDir/bin/edgeR.R bwa ;
        fi &
    if [ $skip_star == "false" ]; 
        then Rscript $baseDir/bin/edgeR.R star ;
        fi &
    """
}

process Cufflinks{
    publishDir "${params.outdir}/peak_calling/cufflinks", mode: 'link', overwrite: true

    input:
    file bam_bai_file from cufflinks_bam
    file designfile

    output:
    file "*" into cufflinks_results

    when:
    false

    script:
    skip_tophat2 = params.skip_tophat2
    skip_hisat2 = params.skip_hisat2
    skip_bwa = params.skip_bwa
    skip_star = params.skip_star
    """
    cat designfile.txt > tmp_designfile.txt
    dos2unix tmp_designfile.txt
    if [ $skip_tophat2 == "false" ]; then bash $baseDir/bin/cufflinks.sh tophat2 ; fi &
    if [ $skip_hisat2 == "false" ]; then bash $baseDir/bin/cufflinks.sh hisat2 ; fi &
    if [ $skip_bwa == "false" ]; then bash $baseDir/bin/cufflinks.sh bwa ; fi &
    if [ $skip_star == "false" ]; then bash $baseDir/bin/cufflinks.sh star ; fi &
    """
}