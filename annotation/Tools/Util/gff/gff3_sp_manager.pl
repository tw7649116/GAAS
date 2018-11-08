#!/usr/bin/env perl

#libraries
use strict;
use warnings;
use Data::Dumper;
use Carp;
use Time::Piece;
use Time::Seconds;
use POSIX qw(strftime);
use Getopt::Long;
use IO::File;
use Pod::Usage;
use List::MoreUtils qw(uniq);
use Bio::DB::Fasta;
use Bio::Tools::GFF;
use BILS::Handler::GFF3handler qw(:Ok);
use BILS::GFF3::Statistics qw(:Ok);
use BILS::Handler::GXFhandler qw(:Ok);
# END libraries

my $header = qq{
########################################################
# BILS 2018 - Sweden                                   #  
# jacques.dainat\@nbis.se                               #
# Please cite NBIS (www.nbis.se) when using this tool. #
########################################################
};

# PARAMETERS - OPTION
my $opt_reffile;
my $opt_output;
my $opt_BlastFile;
my $opt_InterproFile;
my $opt_name=undef;
my $opt_nameU;
my $optFillFrame;
my $optForceFillFrame;
my $opt_removeUTR;
my $opt_removemRNAduplicated;
my $opt_verbose=undef;
my $opt_help = 0;
my $opt_blastEvalue=10;
my $opt_dataBase = undef;
my $opt_pe = 5;
# END PARAMETERS - OPTION

# for ID name
my $nbGeneName;
my $nbmRNAname;
my $nbCDSname;
my $nbExonName;
my $nbOTHERName;
my $nbUTRName;
my $nbRepeatName;
# END ID name

# FOR FUNCTIONS BLAST#
my %nameBlast;
my %geneNameBlast;
my %mRNANameBlast;
my %mRNAproduct;
my %geneNameGiven;
my %duplicateNameGiven;
my $nbDuplicateNameGiven=0;
my $nbDuplicateName=0;
my $nbNamedGene=0;
my $nbGeneNameInBlast=0;
# END FOR FUNCTION BLAST#

# FOR FUNCTIONS INTERPRO#
my %TotalTerm;
my %finalID;
my %GeneAssociatedToTerm;
my %mRNAAssociatedToTerm;
my %functionData;
my %functionDataAdded;
my %functionOutput;
my %functionStreamOutput;
my %geneWithoutFunction;
my %geneWithFunction;
my $nbmRNAwithoutFunction=0;
my $nbmRNAwithFunction=0;
my $nbGeneWithGOterm=0;
my $nbTotalGOterm=0;
# END FOR FUNCTION INTERPRO#

# OPTION MANAGMENT
my @copyARGV=@ARGV;
if ( !GetOptions( 'f|ref|reffile|gff|gff3=s' => \$opt_reffile,
                  'b|blast=s' => \$opt_BlastFile,
                  'd|db=s' => \$opt_dataBase,
                  'be|blast_evalue=i' => \$opt_blastEvalue,
		  'pe=i' => \$opt_pe,
                  'i|interpro=s' => \$opt_InterproFile,
                  'id=s' => \$opt_name,
                  'idau=s' => \$opt_nameU,               
                  'gf=i'      => \$nbGeneName,
                  'mf=i'      => \$nbmRNAname,
                  'cf=i'      => \$nbCDSname,
                  'ef=i'      => \$nbExonName,
                  'uf=i'      => \$nbUTRName,
                  'of=i'      => \$nbOTHERName,
                  'rf=i'      => \$nbRepeatName,
                  'ff'      => \$optFillFrame,
                  'o|output=s'      => \$opt_output,
                  'v'      => \$opt_verbose,
                  'h|help!'         => \$opt_help ) )
{
    pod2usage( { -message => 'Failed to parse command line',
                 -verbose => 1,
                 -exitval => 1 } );
}

if ($opt_help) {
    pod2usage( { -verbose => 2,
                 -exitval => 2,
                 -message => "$header\n" } );
}

if ( ! (defined($opt_reffile)) ){
    pod2usage( {
           -message => "$header\nAt least 1 parameter is mandatory:\nInput reference gff file (--f)\n\n".
           "Many optional parameters are available. Look at the help documentation to know more.\n",
           -verbose => 0,
           -exitval => 1 } );
}

# counters for ids initialisation
if (! $nbGeneName){$nbGeneName=1};
if (! $nbmRNAname){$nbmRNAname=1};
if (! $nbCDSname){$nbCDSname=1};
if (! $nbExonName){$nbExonName=1};
if (! $nbUTRName){$nbUTRName=1};
if (! $nbOTHERName){$nbOTHERName=1};
if (! $nbRepeatName){$nbRepeatName=1};


#################################################
####### START Manage files (input output) #######
#################################################


if($opt_pe>5 or $opt_pe<1){
	print "Error the Protein Existence (PE) value must be between 1 and 5\n";exit; 
}

my $streamBlast = IO::File->new();
my $streamInter = IO::File->new();

# Manage Blast File
if (defined $opt_BlastFile){
  if (! $opt_dataBase){
    print "To use the blast output we also need the fasta of the database used for the blast (--db)\n";exit;
  }
  $streamBlast->open( $opt_BlastFile, 'r' ) or croak( sprintf( "Can not open '%s' for reading: %s", $opt_BlastFile, $! ) );
}

# Manage Interpro file
if (defined $opt_InterproFile){
  $streamInter->open( $opt_InterproFile, 'r' ) or croak( sprintf( "Can not open '%s' for reading: %s", $opt_InterproFile, $! ) );
}

##########################
##### Manage Output ######
my @outputTab;

if (defined($opt_output) ) {
  if (-f $opt_output){
      print "Cannot create a directory with the name $opt_output because a file with this name already exists.\n";exit();
  }
  if (-d $opt_output){
      print "The output directory choosen already exists. Please geve me another Name.\n";exit();
  }
  #### Case 1 => option ouput option onlyStat
  mkdir $opt_output;

  my $ostreamReport=IO::File->new(">".$opt_output."/report.txt" ) or
  croak( sprintf( "Can not open '%s' for writing %s", $opt_output."/report.txt", $! ));
  push (@outputTab, $ostreamReport);

  #### Case 2 => option ouput NO option onlyStat
  my $ostreamCoding=Bio::Tools::GFF->new(-file => ">".$opt_output."/AllFeatures.gff", -gff_version => 3 ) or
  croak(sprintf( "Can not open '%s' for writing %s", $opt_output."AllFeatures.gff", $! ));
  push (@outputTab, $ostreamCoding);
  
  my $ostreamNormalGene=Bio::Tools::GFF->new(-file => ">".$opt_output."/codingGeneFeatures.gff", -gff_version => 3 ) or
  croak( sprintf( "Can not open '%s' for writing %s", $opt_output."/codingGeneFeatures.gff", $! ));
  push (@outputTab, $ostreamNormalGene);

  my $ostreamOtherRNAGene=Bio::Tools::GFF->new(-file => ">".$opt_output."/otherRNAfeatures.gff", -gff_version => 3 ) or
  croak(sprintf( "Can not open '%s' for writing %s", $opt_output."/otherRNAfeatures.gff", $! ));
  push (@outputTab, $ostreamOtherRNAGene);

  my $ostreamRepeats=Bio::Tools::GFF->new(-file => ">".$opt_output."/repeatsFeatures.gff", -gff_version => 3 )or
  croak( sprintf( "Can not open '%s' for writing %s", $opt_output."/repeatsFeatures.gff", $! ));
  push (@outputTab, $ostreamRepeats);

}
### Case 3 => No output option => everithing will be display on screen. 
### Case 4 => If option onlyStat provided the script will stop before writting results.
else {
  my $ostreamReport = \*STDOUT or die ( sprintf( "Can not open '%s' for writing %s", "STDOUT", $! ));
  push (@outputTab, $ostreamReport);

  my $ostream  = IO::File->new();
  $ostream->fdopen( fileno(STDOUT), 'w' ) or croak( sprintf( "Can not open STDOUT for writing: %s", $! ) );
  my $outputGFF = Bio::Tools::GFF->new( -fh => $ostream, -gff_version => 3) or croak( sprintf( "Can not open STDOUT for writing: %s", $! ) );

  #my $outputGFF = Bio::Tools::GFF->new( \*STDOUT, -gff_version => 3 ) or
  #croak( sprintf( "Can not open STDOUT for writing: %s", $! ) );
  push (@outputTab, $outputGFF);
  push (@outputTab, $outputGFF);
  push (@outputTab, $outputGFF);
  push (@outputTab, $outputGFF);
  push (@outputTab, $outputGFF); ### Creation of a list of output stream <= In this case every time the same ! Because it for display to the screen                                 
}

###############################################
####### END Manage files (input output) #######
###############################################
#my $stringPrint = strftime "%m/%d/%Y at %Hh%Mm%Ss", localtime;
my $stringPrint = strftime "%m/%d/%Y", localtime;

$stringPrint .= "\nusage: $0 @copyARGV\n".
                "vvvvvvvvvvvvvvvvvvvvvvvvvvvvv\n".
                "vvvvvvvv OPTION INFO vvvvvvvv\n\n";

my $prefixName=undef;
if ($opt_name){
  $prefixName=$opt_name;
  $stringPrint .= "->IDs will be changed using $opt_name as prefix.\nIn the case of discontinuous features (i.e. a single feature that exists over multiple genomic locations) the same ID may appear on multiple lines.".
  " All lines that share an ID collectively represent a signle feature.\n";
}
if ($opt_nameU){
  $stringPrint .= "->IDs will be changed using $opt_nameU as prefix. Id of features that share an ID collectively will be change in different and uniq ID.\n";
  $prefixName=$opt_nameU;
}
if($optFillFrame or $optForceFillFrame){
  $stringPrint .= "->CDS frame will be fill\n";
}
$stringPrint .= "\n^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n\n";

# Display
$outputTab[0]->print($stringPrint);
if($opt_output){ print_time("$stringPrint");} # When ostreamReport is a file we have to also display on screen



                  #          +------------------------------------------------------+
                  #          |+----------------------------------------------------+|
                  #          ||                       MAIN                         ||
                  #          |+----------------------------------------------------+|
                  #          +------------------------------------------------------+

######################
### Parse GFF input #
my ($hash_omniscient, $hash_mRNAGeneLink) = BILS::Handler::GXFhandler->slurp_gff3_file_JD($opt_reffile);
print_time("Parsing Finished\n\n");
### END Parse GFF input #
#########################

#Print directly what has been read 
if($opt_verbose){
  my $stat = gff3_statistics($hash_omniscient);
  foreach my $info (@$stat){
      $outputTab[0]->print("$info");
  }
}

################################
# MANAGE FUNCTIONAL INPUT FILE #

#####################
# Manage Blast File #
my $db;
my %allIDs;
if (defined $opt_BlastFile){
  # read fasta file and save info in memory
  print ("look at the fasta database\n");
  $db = Bio::DB::Fasta->new($opt_dataBase);
  # save ID in lower case to avoid cast problems
  my @ids      = $db->get_all_primary_ids;
  foreach my $id (@ids ){$allIDs{lc($id)}=$id;}
  print_time("Parsing Finished\n\n");
  
  # parse blast output
  print( "Reading features from $opt_BlastFile...\n");
  parse_blast($streamBlast, $opt_blastEvalue, $hash_mRNAGeneLink);
}

########################
# Manage Interpro File #
if (defined $opt_InterproFile){
  parse_interpro_tsv($streamInter,$opt_InterproFile);
  
  # create streamOutput
  if($opt_output){
    foreach my $type (keys %functionData){
      my $ostreamFunct = IO::File->new(); 
      $ostreamFunct->open( $opt_output."/$type.txt", 'w' ) or
          croak(
              sprintf( "Can not open '%s' for writing %s", $opt_output."/$type.txt", $! )
          );
      $functionStreamOutput{$type}=$ostreamFunct;
    }
  }
}
# END MANAGE FUNCTIONAL INPUT FILE #
####################################

#################################
# GO THROUGH OMISCIENT          # Will create

my %omniscient_gene;
my %omniscient_other;
my %omniscient_repeat;
my @list_geneID_l1;
my @list_OtherRnaID_l1;
my @list_repeatID_l1;
#################
# create list by 3 type of feature (gene, trna, repeats). Allows to create different outputs

# level 1
foreach my $primary_tag_level1 (keys %{$hash_omniscient->{'level1'}}){ # primary_tag_level1 = gene or repeat etc...
  foreach my $id_level1 (keys %{$hash_omniscient->{'level1'}{$primary_tag_level1}}){
    if($primary_tag_level1 =~ /repeat/){
      push(@list_repeatID_l1, $id_level1)
    }
    else{
      # get one level2 feature to check wich level1 feature it is
      foreach my $primary_tag_level2 (keys %{$hash_omniscient->{'level2'}}){ # primary_tag_level2 = mrna or mirna or ncrna or trna etc...        
        if ( exists ($hash_omniscient->{'level2'}{$primary_tag_level2}{$id_level1} ) ){
          my $one_feat=@{$hash_omniscient->{'level2'}{$primary_tag_level2}{$id_level1}}[0];
          if(lc($one_feat->primary_tag) eq "mrna"){
            push(@list_geneID_l1, $id_level1);
            last;
          }
          else{
            push(@list_OtherRnaID_l1, $id_level1);
            last;
          }
        }
      }
    }
  }
}

##########################
# create sub omniscients
my %hash_of_omniscient;
if(@list_geneID_l1){
  fill_omniscient_from_other_omniscient_level1_id(\@list_geneID_l1, $hash_omniscient, \%omniscient_gene);
  $hash_of_omniscient{'Coding_Gene'}=\%omniscient_gene;
}
if(@list_OtherRnaID_l1){
  fill_omniscient_from_other_omniscient_level1_id(\@list_OtherRnaID_l1, $hash_omniscient, \%omniscient_other);
  $hash_of_omniscient{'Non_Coding_Gene'}=\%omniscient_other;
}
if(@list_repeatID_l1){
  fill_omniscient_from_other_omniscient_level1_id(\@list_repeatID_l1, $hash_omniscient, \%omniscient_repeat);
  $hash_of_omniscient{'Repeat'}=\%omniscient_repeat;
}

##############
# STATISTICS #
foreach my $key_hash (keys %hash_of_omniscient){
  $outputTab[0]->print("Information about $key_hash\n");
  if($opt_output){print "Information about $key_hash\n";} # When ostreamReport is a file we have to also display on screen
  my $hash_ref = $hash_of_omniscient{$key_hash};
  my $stat;
  my $distri;
  ($stat, $distri) = gff3_statistics($hash_ref);

  #print statistics
  foreach my $infoList (@$stat){
    foreach my $info (@$infoList){
      $outputTab[0]->print("$info");
      if($opt_output){print "$info";} # When ostreamReport is a file we have to also display on screen
    }
    $outputTab[0]->print("\n");
    if($opt_output){print "\n";} # When ostreamReport is a file we have to also display on screen
  }
}

# END STATISTICS #
##################

###################
#Fil frame is asked
if($optFillFrame){
  print_time( "fill frame information\n");
  foreach my $key_hash (keys %hash_of_omniscient){
    my $hash_ref = $hash_of_omniscient{$key_hash}; 
    fil_cds_frame($key_hash);
  }
}

###########################
# change FUNCTIONAL information if asked for
if ($opt_BlastFile || $opt_InterproFile ){#|| $opt_BlastFile || $opt_InterproFile){
    print_time( "load FUNCTIONAL information\n" );
    my $hash_ref = $hash_of_omniscient{'Coding_Gene'};

    #################
    # == LEVEL 1 == #
    #################
    foreach my $primary_tag_level1 (keys %{$hash_ref ->{'level1'}}){ # primary_tag_level1 = gene or repeat etc...
      foreach my $id_level1 (keys %{$hash_ref ->{'level1'}{$primary_tag_level1}}){
        
        my $feature_level1=$hash_ref->{'level1'}{$primary_tag_level1}{$id_level1};
        # Clean NAME attribute
        if($feature_level1->has_tag('Name')){
          $feature_level1->remove_tag('Name');
        }

        #Manage Name if otpion setting
        if( $opt_BlastFile ){
          if (exists ($geneNameBlast{$id_level1})){
            create_or_replace_tag($feature_level1, 'Name', $geneNameBlast{$id_level1});
            $nbNamedGene++;
            
            # Check name duplicated given
            my $nameClean=$geneNameBlast{$id_level1};
            $nameClean =~ s/_([2-9]{1}[0-9]*|[0-9]{2,})*$//;
            
            my $nameToCompare;
            if(exists ($nameBlast{$nameClean})){ # We check that is really a name where we added the suffix _1
              $nameToCompare=$nameClean;
            }
            else{$nameToCompare=$geneNameBlast{$id_level1};} # it was already a gene_name like BLABLA_12

            if(exists ($geneNameGiven{$nameToCompare})){
                $nbDuplicateNameGiven++; # track total
                $duplicateNameGiven{$nameToCompare}++; # track diversity
            }
            else{$geneNameGiven{$nameToCompare}++;} # first time we have given this name
          }
        }

        #################
        # == LEVEL 2 == #
        #################
        foreach my $primary_tag_key_level2 (keys %{$hash_ref->{'level2'}}){ # primary_tag_key_level2 = mrna or mirna or ncrna or trna etc...
          
          if ( exists_keys ($hash_ref, ('level2', $primary_tag_key_level2, $id_level1) ) ){
            foreach my $feature_level2 ( @{$hash_ref->{'level2'}{$primary_tag_key_level2}{$id_level1}}) {

              my $level2_ID = lc($feature_level2->_tag_value('ID'));
              # Clean NAME attribute
              if($feature_level2->has_tag('Name')){
                $feature_level2->remove_tag('Name');
              }
              
              #Manage Name if option set
              if($opt_BlastFile){
                if (exists ($mRNANameBlast{$level2_ID})){
                  my $mRNABlastName=$mRNANameBlast{$level2_ID};
                  create_or_replace_tag($feature_level2, 'Name', $mRNABlastName);
                }
                my $productData=printProductFunct($level2_ID);
                if ($productData ne ""){
                  create_or_replace_tag($feature_level2, 'product', $productData);
                }
                else {
                  create_or_replace_tag($feature_level2, 'product', "hypothetical protein");
                } #Case where the protein is not known
              }

              # print function if option
              if($opt_InterproFile){
                my $parentID=$feature_level2->_tag_value('Parent');

                if (addFunctions($feature_level2, $opt_output)){
                  $nbmRNAwithFunction++;$geneWithFunction{$parentID}++;
                  if(exists ($geneWithoutFunction{$parentID})){
                    delete $geneWithoutFunction{$parentID};
                  }
                }
                else{
                  $nbmRNAwithoutFunction++;
                  if(! exists ($geneWithFunction{$parentID})){
                    $geneWithoutFunction{$parentID}++;
                  }
                }
              }
            }
          }
        }
      } 
    }
}


###########################
# change names if asked for
if ($opt_nameU || $opt_name ){#|| $opt_BlastFile || $opt_InterproFile){
  print_time( "load NAME information\n");
  foreach my $key_hash (keys %hash_of_omniscient){
    my $hash_ref = $hash_of_omniscient{$key_hash};

    my %hash_sortBySeq;
    foreach my $tag_level1 ( keys %{$hash_ref->{'level1'}}){
      foreach my $level1_id ( keys %{$hash_ref->{'level1'}{$tag_level1}}){
        my $position=$hash_ref->{'level1'}{$tag_level1}{$level1_id}->seq_id;
        push (@{$hash_sortBySeq{$position}{$tag_level1}}, $hash_ref->{'level1'}{$tag_level1}{$level1_id});
      }
    } 

    #################
    # == LEVEL 1 == #
    #################
    #Read by seqId to sort properly the output by seq ID
    foreach my $seqid (sort alphaNum keys %hash_sortBySeq){ # loop over all the feature level1

      foreach my $primary_tag_level1 (sort {$a cmp $b} keys %{$hash_sortBySeq{$seqid}}){

        foreach my $feature_level1 ( sort {$a->start <=> $b->start} @{$hash_sortBySeq{$seqid}{$primary_tag_level1}}){
          my $level1_ID=$feature_level1->_tag_value('ID');
          my $id_level1 = lc($level1_ID);
          my $newID_level1=undef;
          #print_time( "Next gene $id_level1\n");

          #keep track of Maker ID
          if($opt_BlastFile){#In that case the name given by Maker is removed from ID and from Name. We have to kee a track
            create_or_replace_tag($feature_level1, 'makerName', $level1_ID);
          }

          if(lc($primary_tag_level1) =~ /repeat/ ){
            $newID_level1 = manageID($prefixName,$nbRepeatName,'R'); 
            $nbRepeatName++;
            create_or_replace_tag($feature_level1, 'ID', $newID_level1);
          }
          else{
            $newID_level1 = manageID($prefixName,$nbGeneName,'G'); 
            $nbGeneName++; 
            create_or_replace_tag($feature_level1, 'ID', $newID_level1);
          }

          $finalID{$feature_level1->_tag_value('ID')}=$newID_level1;
          #################
          # == LEVEL 2 == #
          #################
          foreach my $primary_tag_key_level2 (keys %{$hash_ref->{'level2'}}){ # primary_tag_key_level2 = mrna or mirna or ncrna or trna etc...
            
            if ( exists_keys ($hash_ref, ('level2', $primary_tag_key_level2, $id_level1) ) ){
              foreach my $feature_level2 ( @{$hash_ref->{'level2'}{$primary_tag_key_level2}{$id_level1}}) {

                my $level2_ID = $feature_level2->_tag_value('ID');
                my $newID_level2=undef;
                
                #keep track of Maker ID
                if($opt_InterproFile){#In that case the name given by Maker is removed from ID and from Name. We have to kee a track
                  create_or_replace_tag($feature_level2, 'makerName', $level2_ID);
                }

                if(lc($feature_level2) =~ /repeat/ ){
                  print "What should we do ? implement something. L1 and l2 repeats will have same name ...\n";exit;
                }
                else{
                  $newID_level2 = manageID($prefixName,$nbmRNAname,"T");
                  $nbmRNAname++; 
                  create_or_replace_tag($feature_level2, 'ID', $newID_level2);
                  create_or_replace_tag($feature_level2, 'Parent', $newID_level1);
                }
                
                $finalID{$level2_ID}=$newID_level2;
                #################
                # == LEVEL 3 == #
                #################
               
                foreach my $primary_tag_level3 (keys %{$hash_ref->{'level3'}}){ # primary_tag_key_level3 = cds or exon or start_codon or utr etc...

                    if ( exists_keys ($hash_ref,('level3',$primary_tag_level3, lc($level2_ID)) ) ){

                      foreach my $feature_level3 ( @{$hash_ref->{'level3'}{$primary_tag_level3}{lc($level2_ID)}}) {

                        #keep track of Maker ID
                        my $level3_ID = $feature_level3->_tag_value('ID');
                        if($opt_InterproFile){#In that case the name given by Maker is removed from ID and from Name. We have to kee a track
                          create_or_replace_tag($feature_level3, 'makerName', $level3_ID);
                        }

                        my $newID_level3 ="";
                        if($primary_tag_level3 =~ /exon/ ){
                          $newID_level3 = manageID($prefixName,$nbExonName,'E'); 
                          $nbExonName++;
                          create_or_replace_tag($feature_level3, 'ID', $newID_level3);
                          create_or_replace_tag($feature_level3, 'Parent', $newID_level2);

                        }
                        elsif($primary_tag_level3 =~ /cds/){
                          $newID_level3 = manageID($prefixName,$nbCDSname,'C'); 
                          if($opt_nameU){$nbCDSname++;}
                          create_or_replace_tag($feature_level3, 'ID', $newID_level3);
                          create_or_replace_tag($feature_level3, 'Parent', $newID_level2);
                        }

                        elsif($primary_tag_level3 =~ /utr/){
                          $newID_level3 = manageID($prefixName,$nbUTRName,'U');
                          if($opt_nameU){$nbUTRName++;}
                          create_or_replace_tag($feature_level3, 'ID', $newID_level3);
                          create_or_replace_tag($feature_level3, 'Parent', $newID_level2);
                        }
                        else{
                          $newID_level3 = manageID($prefixName,$nbOTHERName,'O');
                          $nbOTHERName++;
                          create_or_replace_tag($feature_level3, 'ID', $newID_level3);
                          create_or_replace_tag($feature_level3, 'Parent', $newID_level2);                        
                        }
                        $finalID{$level3_ID}=$newID_level3;
                      }
                      #save the new l3 into the new l2 id name
                      $hash_ref->{'level3'}{$primary_tag_level3}{lc($newID_level2)} = delete $hash_ref->{'level3'}{$primary_tag_level3}{lc($level2_ID)} # delete command return the value before deteling it, so we just transfert the value 
                    }
                    if ($opt_name and  $primary_tag_level3 =~ /utr/){$nbUTRName++;} # with this option we increment UTR name only for each UTR 
                    if ($opt_name and  $primary_tag_level3 =~ /cds/){$nbCDSname++;} # with this option we increment cds name only for each cds 
                }
              }
              if($newID_level1){
                $hash_ref->{'level2'}{$primary_tag_key_level2}{lc($newID_level1)} = delete $hash_ref->{'level2'}{$primary_tag_key_level2}{$id_level1}; # modify the id key of the hash. The delete command return the value before deteling it, so we just transfert the value 
              } 
            }
          }
        
          if($newID_level1){
            $hash_ref->{'level1'}{$primary_tag_level1}{lc($newID_level1)} = delete $hash_ref->{'level1'}{$primary_tag_level1}{$id_level1}; # modify the id key of the hash. The delete command return the value before deteling it, so we just transfert the value 
          }
        }
      }
    } 
  }
}

###########################
# RESULT PRINTING
###########################

##############################
# print FUNCITONAL INFORMATION

# first table name\tfunction
if($opt_output){
  foreach my $function_type (keys %functionOutput){
    my $streamOutput=$functionStreamOutput{$function_type};
    foreach my $ID (keys %{$functionOutput{$function_type}}){

      if ($opt_nameU || $opt_name ){
        print $streamOutput  $finalID{$ID}."\t".$functionOutput{$function_type}{$ID}."\n";
      }
      else{
        print $streamOutput  $ID."\t".$functionOutput{$function_type}{$ID}."\n";
      }
    }
  }
}


# NOW summerize
$stringPrint =""; # reinitialise (use at the beginning)
if ($opt_InterproFile){
  #print INFO
  my $lineB=       "___________________________________________________________________________________________________";
  $stringPrint .= " ".$lineB."\n";
  $stringPrint .= "|          | Nb Total term | Nb mRNA with term  | Nb mRNA updated by term | Nb gene updated by term |\n";
  $stringPrint .= "|          | in Annie File |   in Annie File    | in our annotation file  | in our annotation file  |\n";
  $stringPrint .= "|".$lineB."|\n";

  foreach my $type (keys %functionData){
    my $total_type = $TotalTerm{$type};
    my $mRNA_type_Annie = $functionDataAdded{$type};
    my $mRNA_type = keys %{$mRNAAssociatedToTerm{$type}};
    my $gene_type = keys %{$GeneAssociatedToTerm{$type}};
    $stringPrint .= "|".sizedPrint(" $type",10)."|".sizedPrint($total_type,15)."|".sizedPrint($mRNA_type_Annie,20)."|".sizedPrint($mRNA_type,25)."|".sizedPrint($gene_type,25)."|\n|".$lineB."|\n";
  }

  #RESUME TOTAL OF FUNCTION ATTACHED
  my $listOfFunction;
  foreach my $funct (keys %functionData){
    $listOfFunction.="$funct,";
  }
  chop $listOfFunction;
  $stringPrint .= "nb mRNA without Functional annotation ($listOfFunction) = $nbmRNAwithoutFunction\n";
  $stringPrint .= "nb mRNA with Functional annotation ($listOfFunction) = $nbmRNAwithFunction\n";
  my $nbGeneWithoutFunction= keys %geneWithoutFunction;
  $stringPrint .= "nb gene without Functional annotation ($listOfFunction) = $nbGeneWithoutFunction\n";
  my $nbGeneWithFunction= keys %geneWithFunction;
  $stringPrint .= "nb gene with Functional annotation ($listOfFunction) = $nbGeneWithFunction\n";
  
}

if($opt_BlastFile){
  my $nbGeneDuplicated=keys %duplicateNameGiven;
  $nbDuplicateNameGiven=$nbDuplicateNameGiven+$nbGeneDuplicated; # Until now we have counted only name in more, now we add the original name.
  $stringPrint .= "$nbGeneNameInBlast gene names have been retrieved in the blast file. $nbNamedGene gene names have been successfully inferred.\n".
  "Among them there are $nbGeneDuplicated names that are shared at least per two genes for a total of $nbDuplicateNameGiven genes.\n";
  # "We have $nbDuplicateName gene names duplicated ($nbDuplicateNameGiven - $nbGeneDuplicated).";

  if($opt_output){
    my $duplicatedNameOut=IO::File->new(">".$opt_output."/duplicatedNameFromBlast.txt" );
    foreach my $name (sort { $duplicateNameGiven{$b} <=> $duplicateNameGiven{$a} } keys %duplicateNameGiven){
      print $duplicatedNameOut "$name\t".($duplicateNameGiven{$name}+1)."\n";
    }
  }
}


# Display
$outputTab[0]->print("$stringPrint");
if(defined $opt_output){print_time( "$stringPrint" ) ;}

####################
# PRINT IN FILES
####################
#print step
printf("Writing result\n");
if($opt_output){
  #print gene (mRNA)
  print_omniscient(\%omniscient_gene, $outputTab[2]);
  #print other RNA gene
  print_omniscient(\%omniscient_other, $outputTab[3]);
  #print repeat
  print_omniscient(\%omniscient_repeat, $outputTab[4]);
}
else{
  #print gene (mRNA)
  print_omniscient(\%omniscient_gene, $outputTab[1]);
  #print other RNA gene
  print_omniscient(\%omniscient_other, $outputTab[1]);
  #print repeat
  print_omniscient(\%omniscient_repeat, $outputTab[1]);
}
      ######################### 
      ######### END ###########
      #########################
#######################################################################################################################
        ####################
         #     methods    #
          ################
           ##############
            ############
             ##########
              ########
               ######
                ####
                 ##

# print with time
sub print_time{
  my $t = localtime;
  my $line = "[".$t->hms."] @_\n";
  print $line;
}

# each mRNA of a gene has its proper gene name. Most often is the same, and annie added a number at the end. To provide only one gene name, we remove this number and then remove duplicate name (case insensitive).
# If it stay at the end of the process more than one name, they will be concatenated together.
# It removes redundancy intra name.
sub manageGeneNameBlast{
  my ($geneName)=@_;
  foreach my $element (keys %$geneName){
    my @tab=@{$geneName->{$element}};
    
    my %seen;
    my @unique;
    for my $w (@tab) { # remove duplicate in list case insensitive
      $w =~ s/_[0-9]+$// ;
      next if $seen{lc($w)}++;
      push(@unique, $w);
    }

    my $finalName="";
    my $cpt=0;
    foreach my $name (@unique){  #if several name we will concatenate them together
        if ($cpt == 0){
          $finalName .="$name";
        }
        else{$finalName .="_$name"}
    }
    $geneName->{$element}=$finalName;
    $nameBlast{lc($finalName)}++;
  }
}

# creates gene ID correctly formated (PREFIX,TYPE,NUMBER) like HOMSAPG00000000001 for a Homo sapiens gene.
sub manageID{
  my ($prefix,$nbName,$type)=@_;
  my $result="";
  my $numberNum=11;
  my $GoodNum="";
  for (my $i=0; $i<$numberNum-length($nbName); $i++){
    $GoodNum.="0";
  }
  $GoodNum.=$nbName;
  $result="$prefix$type$GoodNum";

  return $result;
}

# Create String containing the product information associated to the mRNA
sub printProductFunct{
  my ($refname)=@_;
  my $String="";
  my $first="yes";
  if (exists $mRNAproduct{$refname}){
    foreach my $element (@{$mRNAproduct{$refname}})
    { 
      if($first eq "yes"){
        $String.="$element";
        $first="no";
      }
      else{$String.=",$element";}
    }
  }
  return $String;
}

sub addFunctions{
  my ($feature, $opt_output)=@_;

  my $functionAdded=undef;
  my $ID=lc($feature->_tag_value('ID'));
  foreach my $function_type (keys %functionData){
    
    
    if(exists ($functionData{$function_type}{$ID})){
      $functionAdded="true";

      my $data_list;

      if(lc($function_type) eq "go"){
        foreach my $data (@{$functionData{$function_type}{$ID}}){
          $feature->add_tag_value('Ontology_term', $data);
          $data_list.="$data,";
	  $functionDataAdded{$function_type}++;
        }
      }
      else{
        foreach my $data (@{$functionData{$function_type}{$ID}}){
          $feature->add_tag_value('Dbxref', $data);
          $data_list.="$data,";
	  $functionDataAdded{$function_type}++;
        }
      }

      if ($opt_output){
          my $ID = $feature->_tag_value('ID');
          chop $data_list;
          $functionOutput{$function_type}{$ID}=$data_list;
        }
    }
  }
  return $functionAdded;
}

# method to par annie blast file
sub parse_blast {
  my($file_in, $opt_blastEvalue, $hash_mRNAGeneLink) = @_;

  my %candidates; 
  #catch all candidates first (better candidate for each mRNA)
  while( my $line = <$file_in>)  {
    my @values = split(/\t/, $line);
     my $l2_name = lc($values[0]);
     my $prot_name = $values[1];
     my $evalue = $values[10];
     print "Evalue: ".$evalue."\n" if($opt_verbose);

     #if does not exist fill it if over the minimum evalue
    if (! exists_keys(\%candidates,($l2_name)) or @{$candidates{$l2_name}}> 2 ){ # the second one means we saved an error message as candidates we still have to try to find a proper one
      if( $evalue < $opt_blastEvalue ) {
	my $protID_correct=undef;
    	if( exists $allIDs{lc($prot_name)}){
      		$protID_correct = $allIDs{lc($prot_name)};
      		my $header = $db->header( $protID_correct );
		if ($header =~ m/GN=/){
			if($header =~ /PE=([1-5])\s/){
				if($1 <= $opt_pe){
					$candidates{$l2_name}=[$header, $evalue];
				}
				
			}
			else{print "No Protein Existence (PE) information in this header: $header\n";}
		}
		else{ 
			print "No gene name (GN=) in this header $header\n" if($opt_verbose); 
			$candidates{$l2_name}=["error", $evalue, $prot_name."-".$l2_name];
		}
	}
	else{
		print "ERROR $prot_name not found among the db! You probably didn't give to me the same fasta file than the one used for the blast. (l2=$l2_name)\n" if($opt_verbose);
		$candidates{$l2_name}=["error", $evalue, $prot_name."-".$l2_name];
	}
      }
    }
    elsif( $evalue > $candidates{$l2_name}[1] ) { # better evalue for this record
	my $protID_correct=undef;
        if( exists $allIDs{lc($prot_name)}){
                $protID_correct = $allIDs{lc($prot_name)};
                my $header = $db->header( $protID_correct );
                if ($header =~ m/GN=/){
                      if($header =~ /PE=([1-5])\s/){
                                if($1 <= $opt_pe){
                                        $candidates{$l2_name}=[$header, $evalue];
                                }

                        }
                        else{print "No Protein Existence (PE) information in this header: $header\n";}                        
                }
                else{ print "No gene name (GN=) in this header $header\n" if($opt_verbose); }
        }
	else{print "ERROR $prot_name not found among the db! You probably didn't give to me the same fasta file than the one used for the blast. (l2=$l2_name)\n" if($opt_verbose);}      
    }
  }

  my $nb_desc = keys %candidates;
  print "We have $nb_desc description candidates.\n";

  my %geneName; 
  my %linkBmRNAandGene;
  #go through all candidates
  foreach my $l2 (keys %candidates){
      if( $candidates{$l2}[0] eq "error" ){
	print "error nothing found for $candidates{$l2}[2]\n";next;
      }
      my $header = $candidates{$l2}[0];
      print "header: ".$header."\n" if($opt_verbose);
      if ($header =~ m/(^[^\s]+)(.+?(?= \w{2}=))(.+)/){
	      my $protID = $1;
	      my $description = $2;
	      my $theRest = $3;
	      $theRest =~ s/\n//g;
	      $theRest =~ s/\r//g;
	      my $nameGene = undef;
	      push ( @{ $mRNAproduct{$l2} }, $description );     
	
	      #deal with the rest
	      my %hash_rest;
	      my $tuple=undef;
	      while ($theRest){
	  	($theRest, $tuple) = stringCatcher($theRest);     
	 	my ($type,$value) = split /=/,$tuple;
		#print "$protID: type:$type --- value:$value\n";
		$hash_rest{lc($type)}=$value;
	      }
	      if(exists($hash_rest{"gn"})){
		$nameGene=$hash_rest{"gn"};
	        
		if(exists_keys ($hash_mRNAGeneLink,($l2)) ){
			my $geneID = $hash_mRNAGeneLink->{$l2};      
	       	 	#print "push $geneID $nameGene\n";
			push ( @{ $geneName{lc($geneID)} }, lc($nameGene) );
	        	push( @{ $linkBmRNAandGene{lc($geneID)}}, lc($l2)); # save mRNA name for each gene name 
		}
		else{print "No parent found for $l2 (defined in the blast file) in hash_mRNAGeneLink (created by the gff file).\n";}
	}
	else{print "Header from the db fasta file doesn't match the regular expression: $header\n";}
     }
  }
  
  ################
   # secondly Manage NAME (If several)
   manageGeneNameBlast(\%geneName); # Remove redundancy to have only one name for each gene
  
   #Then CLEAN NAMES REDUNDANCY inter gene
   my %geneNewNameUsed;
   foreach my $geneID (keys %geneName){
     $nbGeneNameInBlast++;
    
     my @mRNAList=@{$linkBmRNAandGene{$geneID}};
     my $String = $geneName{$geneID};
 #    print "$String\n";
     if (! exists( $geneNewNameUsed{$String})){
       $geneNewNameUsed{$String}++;
       $geneNameBlast{$geneID}=$String;
       # link name to mRNA and and isoform name _1 _2 _3 if several mRNA
       my $cptmRNA=1;
       if ($#mRNAList != 0) {
         foreach my $mRNA (@mRNAList){
           $mRNANameBlast{$mRNA}=$String."_iso".$cptmRNA;
           $cptmRNA++;
         }
       }
       else{$mRNANameBlast{$mRNAList[0]}=$String;}
     }
     else{ #in case where name was already used, we will modified it by addind a number like "_2"
       $nbDuplicateName++;
       $geneNewNameUsed{$String}++;
       my $nbFound=$geneNewNameUsed{$String};
       $String.="_$nbFound";
       $geneNewNameUsed{$String}++;
       $geneNameBlast{$geneID}=$String;
       # link name to mRNA and and isoform name _1 _2 _3 if several mRNA
       my $cptmRNA=1;  
       if ($#mRNAList != 0) {
         foreach my $mRNA (@mRNAList){
           $mRNANameBlast{$mRNA}=$String."_iso".$cptmRNA;
           $cptmRNA++;
         }
       }
       else{$mRNANameBlast{$mRNAList[0]}=$String;}
     }
   }
}

#uniprotHeader string spliter
sub stringCatcher{
    my($String) = @_;
    my $newString=undef;

    if ( $String =~ m/(\w{2}=.+?(?= \w{2}=))(.+)/ ) {
        $newString = substr $String, length($1)+1;
    	return ($newString, $1); 
    }
    else{ return (undef, $String); }
}

# method to parse Interpro file
sub parse_interpro_tsv {
  my($file_in,$fileName) = @_;
  print( "Reading features from $fileName...\n");

  while( my $line = <$file_in>)  {    
    
    my @values = split(/\t/, $line);
    my $sizeList = @values;   
    my $mRNAID=lc($values[0]);

      #Check for the specific DB
      my $db_name=$values[3];
      my $db_value=$values[4];
      my $db_tuple=$db_name.":".$db_value;
      print "Specific dB: ".$db_tuple."\n" if($opt_verbose);

      if (! grep( /^\Q$db_tuple\E$/, @{$functionData{$db_name}{$mRNAID}} ) ) {   #to avoid duplicate
	      $TotalTerm{$db_name}++;
	      push ( @{$functionData{$db_name}{$mRNAID}} , $db_tuple );
	      if ( exists $hash_mRNAGeneLink->{$mRNAID}){ ## check if exists among our current gff annotation file analyzed
	        $mRNAAssociatedToTerm{$db_name}{$mRNAID}++;
	        $GeneAssociatedToTerm{$db_name}{$hash_mRNAGeneLink->{$mRNAID}}++;
	      }
	}
   
      #check for interpro
      if( $sizeList>11 ){
        my $db_name="InterPro";
        my $interpro_value=$values[11];
        $interpro_value=~ s/\n//g;
	my $interpro_tuple = "InterPro:".$interpro_value;
        print "interpro dB: ".$interpro_tuple."\n" if($opt_verbose);

	if (! grep( /^\Q$interpro_tuple\E$/, @{$functionData{$db_name}{$mRNAID}} ) ) {	#to avoid duplicate
	        $TotalTerm{$db_name}++;
	        push ( @{$functionData{$db_name}{$mRNAID}} , $interpro_tuple );
	        if ( exists $hash_mRNAGeneLink->{$mRNAID}){ ## check if exists among our current gff annotation file analyzed	
	          $mRNAAssociatedToTerm{$db_name}{$mRNAID}++;
	          $GeneAssociatedToTerm{$db_name}{$hash_mRNAGeneLink->{$mRNAID}}++;
	        }
	}
      }

      #check for GO
      if( $sizeList>13 ){
        my $db_name="GO";
        my $go_flat_list = $values[13];
        $go_flat_list=~ s/\n//g;
        my @go_list = split(/\|/,$go_flat_list); #cut at character | 
        foreach my $go_tuple (@go_list){
          print "GO term: ".$go_tuple."\n" if($opt_verbose);

	if (! grep( /^\Q$go_tuple\E$/, @{$functionData{$db_name}{$mRNAID}} ) ) { #to avoid duplicate
	          $TotalTerm{$db_name}++;
	          push ( @{$functionData{$db_name}{$mRNAID}} , $go_tuple );
	          if ( exists $hash_mRNAGeneLink->{$mRNAID}){ ## check if exists among our current gff annotation file analyzed
	            $mRNAAssociatedToTerm{$db_name}{$mRNAID}++;
	            $GeneAssociatedToTerm{$db_name}{$hash_mRNAGeneLink->{$mRNAID}}++;
	          }
	  }
        }
      }

      #check for pathway
      if( $sizeList>14 ){
        my $pathway_flat_list = $values[14];
        $pathway_flat_list=~ s/\n//g;
        $pathway_flat_list=~ s/ //g;
        my  @pathway_list = split(/\|/,$pathway_flat_list); #cut at character | 
        foreach my $pathway_tuple (@pathway_list){
          my @tuple = split(/:/,$pathway_tuple); #cut at character :
          my $db_name = $tuple[0];
          print "pathway info: ".$pathway_tuple."\n" if($opt_verbose); 
	  
	  if (! grep( /^\Q$pathway_tuple\E$/, @{$functionData{$db_name}{$mRNAID}} ) ) { # to avoid duplicate
	          $TotalTerm{$db_name}++;
	          push ( @{$functionData{$db_name}{$mRNAID}} , $pathway_tuple );
	          if ( exists $hash_mRNAGeneLink->{$mRNAID}){ ## check if exists among our current gff annotation file analyzed
	            $mRNAAssociatedToTerm{$db_name}{$mRNAID}++;
	            $GeneAssociatedToTerm{$db_name}{$hash_mRNAGeneLink->{$mRNAID}}++;
	          }
	  }
        }
      }      
  }
}

sub sizedPrint{
  my ($term,$size) = @_;
  my $result; my $sizeTerm=length($term);
  if ($sizeTerm > $size ){
    $result=substr($term, 0,$size);
    return $result;
  }
  else{
    my $nbBlanc=$size-$sizeTerm;
    $result=$term;
    for (my $i = 0; $i < $nbBlanc; $i++){
      $result.=" ";
    }
    return $result;
  }
}

#Sorting mixed strings => Sorting alphabetically first, then numerically
# how to use: my @y = sort by_number @x;
sub alphaNum {
    my ( $alet , $anum ) = $a =~ /([^\d]+)(\d+)/;
    my ( $blet , $bnum ) = $b =~ /([^\d]+)(\d+)/;
    ( $alet || "a" ) cmp ( $blet || "a" ) or ( $anum || 0 ) <=> ( $bnum || 0 )
}

__END__

=head1 NAME

gff3manager_JD.pl -
The script take a gff3 file as input. -
Without option the script only sort the data. -
With corresponding parameters, it can add functional annotations from <annie> output files
>The blast against Prot Database file from annie allows to fill the field NAME for gene and PRODUCT for mRNA.
>The blast against Interpro Database tsv file from annie allows to fill the DBXREF field with pfam, tigr, interpro and GO terms data.
The script expand exons sharing multiple mRNA (Parent attributes contains multiple parental mRNA). One exon by parental mRNA will be created.
With the <id> option the script will change all the ID field by an Uniq ID created from the given prefix, a letter to specify the kind of feature (G,T,C,E,U), and the feature number.

The result is written to the specified output file, or to STDOUT.
Remark: If there is duplicate in the file they will be removed in the output. In that case you should be informed.

About the TSV format from interproscan:
=======================================

The TSV format presents the match data in columns as follows:

1.Protein Accession (e.g. P51587)
2.Sequence MD5 digest (e.g. 14086411a2cdf1c4cba63020e1622579)
3.Sequence Length (e.g. 3418)
4.Analysis (e.g. Pfam / PRINTS / Gene3D)
5.Signature Accession (e.g. PF09103 / G3DSA:2.40.50.140)
6.Signature Description (e.g. BRCA2 repeat profile)
7.Start location
8.Stop location
9.Score - is the e-value (or score) of the match reported by member database method (e.g. 3.1E-52)
10.Status - is the status of the match (T: true)
11.Date - is the date of the run
12.(InterPro annotations - accession (e.g. IPR002093) - optional column; only displayed if -iprlookup option is switched on)
13.(InterPro annotations - description (e.g. BRCA2 repeat) - optional column; only displayed if -iprlookup option is switched on)
14.(GO annotations (e.g. GO:0005515) - optional column; only displayed if --goterms option is switched on)
15.(Pathways annotations (e.g. REACT_71) - optional column; only displayed if --pathways option is switched on)

P.S: The 9th column contains most of time e-value, but can contain also score (e.g Prosite). To understand the difference: https://myhits.isb-sib.ch/cgi-bin/help?doc=scores.html

About the outfmt 6 from blast:
==============================

 1.  qseqid  query (e.g., gene) sequence id
 2.  sseqid  subject (e.g., reference genome) sequence id
 3.  pident  percentage of identical matches
 4.  length  alignment length
 5.  mismatch  number of mismatches
 6.  gapopen   number of gap openings
 7.  qstart  start of alignment in query
 8.  qend  end of alignment in query
 9.  sstart  start of alignment in subject
 10.   send  end of alignment in subject
 11.   evalue  expect value
 12.   bitscore  bit score

Currently the best e-value win... That means another hit with a lower e-value ( but still over the defined threshold anyway) even if it has a better PE value
 will not be reported.

=head1 SYNOPSIS

    ./gff3manager_JD.pl -f=infile.gff [ -b blast_infile -i interpro_infile.tsv -e --id ABCDEF [-gf 20] -s -utr -utrr 10 --output outfile ]
    ./gff3manager_JD.pl --help

=head1 OPTIONS

=over 8

=item B<-f>, B<--reffile>,B<-ref> , B<--gff> or B<--gff3> 

Input GFF3 file that will be read (and sorted)

=item B<-b> or B<--blast> 

Input blast ( outfmt 6 = tabular )file that will be used to complement the features read from
the first file (specified with B<--ref>).

=item B<--be> or B<--blast_evalue>

 Maximum e-value to keep the annotaiton from the blast file. By default 10.

=item B<--pe>

The PE (protein existence) in the uniprot header indicates the type of evidence that supports the existence of the protein.
You can decide until which protein existence level you want to consider to lift the finctional information. Default 5.

1. Experimental evidence at protein level 
2. Experimental evidence at transcript level 
3. Protein inferred from homology 
4. Protein predicted 
5. Protein uncertain

=item B<-i> or B<--interpro> 

Input interpro file (.tsv) that will be used to complement the features read from
the first file (specified with B<--ref>).

=item B<-id>

This option will changed the id name. It will create from id prefix (usually 6 letters) given as input, uniq IDs like prefixE00000000001. Where E mean exon. Instead E we can have C for CDS, G for gene, T for mRNA, U for Utr.
In the case of discontinuous features (i.e. a single feature that exists over multiple genomic locations) the same ID may appear on multiple lines. All lines that share an ID collectively represent a signle feature.

=item B<-idau>

This option (id all uniq) is similar to -id option but Id of features that share an ID collectively will be change by different and uniq ID.

=item B<-gf>

Usefull only if -id is used.
This option is used to define the number that will be used to begin to number the gene id (gf for "gene from"). By default begin by 1.

=item B<-mf>

Usefull only if -id is used.
This option is used to define the number that will be used to begin to number the mRNA id (mf for "mRNA from"). By default begin by 1.

=item B<-cf>

Useful only if -id is used.
This option is used to define the number that will be used to begin to number the CDS id (cf for "CDS from"). By default begin by 1.

=item B<-ef>

Useful only if -id is used.
This option is used to define the number that will be used to begin to number the exon id (ef for "Exon from"). By default begin by 1.

=item B<-uf>

Useful only if -id is used.
This option is used to define the number that will be used to begin to number the UTR id (uf for "UTR from"). By default begin by 1.

=item B<-rf>

Useful only if -id is used.
This option is used to define the number that will be used to begin to number the repeat id (rf for "Repeat from"). By default begin by 1.

=item B<-ff>

ff means fill frame.
This option is used to add the CDS frame. If frames already exist, the script overwrite them.

=item B<-o> or B<--output>

Output GFF file.  If no output file is specified, the output will be
written to STDOUT.

=item B<-h> or B<--help>

Display this helpful text.

=back

=cut
